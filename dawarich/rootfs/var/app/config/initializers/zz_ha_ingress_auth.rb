# Sign people in from the identity Home Assistant already proved.
#
# Named zz_* so it loads after upstream's devise and omniauth initializers.
#
# Home Assistant puts the signed-in user in X-Remote-User-Id on ingress requests
# and strips any copy the browser sent, so through ingress that header is as
# trustworthy as HA's own login. nginx passes it on, together with the shared
# secret below, only for requests coming from Supervisor's address. Anything
# else, including port 3000 and other containers on the hassio network, arrives
# without an identity and gets the normal login form.
#
# The identity is only ever used to *find* an account, never to change one:
# an existing Dawarich user is adopted by stamping provider/uid on it, which
# leaves its points, tracks and settings exactly as they were.
module HomeAssistantIngressAuth
  PROVIDER = 'home_assistant'
  SECRET_HEADER = 'HTTP_X_DAWARICH_INGRESS_SECRET'
  USER_ID_HEADER = 'HTTP_X_REMOTE_USER_ID'
  USER_NAME_HEADER = 'HTTP_X_REMOTE_USER_NAME'
  DISPLAY_NAME_HEADER = 'HTTP_X_REMOTE_USER_DISPLAY_NAME'
  USER_MAP_PATH = '/data/dawarich/ha_user_map.json'
  # Signing out has to actually sign you out. Without this, the next request
  # would hand the session straight back and the button would look broken.
  OPT_OUT_COOKIE = :dawarich_ingress_auto_login_off
  OPT_OUT_FOR = 30.minutes

  class << self
    def enabled?
      ENV['INGRESS_AUTO_LOGIN'].to_s == 'on' && secret.present?
    end

    def secret
      @secret ||= ENV['INGRESS_AUTH_SECRET'].to_s
    end

    def identity(request)
      return nil unless enabled?
      return nil unless trusted?(request)

      id = header(request, USER_ID_HEADER)
      return nil if id.blank?

      {
        id: id,
        name: header(request, USER_NAME_HEADER),
        display_name: header(request, DISPLAY_NAME_HEADER)
      }
    end

    # Rack hands header values back as ASCII-8BIT, and a name like "Jörg" then
    # blows up anything expecting text (transliterate raises outright). Tag them
    # as the UTF-8 they actually are and drop any invalid bytes.
    def header(request, key)
      request.get_header(key).to_s.dup.force_encoding(Encoding::UTF_8).scrub('').strip
    end

    # Look up, adopt, or (only where it is safe) create. Returns nil to mean
    # "let Devise show the login form", never an exception to the caller.
    def user_for(identity)
      existing = User.find_by(provider: PROVIDER, uid: identity[:id])
      return existing if existing

      release_identity_from_deleted_accounts(identity)

      mapped = mapped_user(identity) || account_named_after(identity)
      return adopt(mapped, identity) if mapped

      create(identity)
    end

    private

    def trusted?(request)
      given = request.get_header(SECRET_HEADER).to_s
      given.bytesize == secret.bytesize &&
        ActiveSupport::SecurityUtils.fixed_length_secure_compare(given, secret)
    rescue StandardError
      false
    end

    def mapped_user(identity)
      email = user_map[identity[:id]]
      return nil if email.blank?

      # Devise downcases addresses on save (case_insensitive_keys), while the
      # map carries admin_email exactly as it was configured. Compare the way
      # the row was actually stored, or an admin_email with a capital letter in
      # it never matches and its owner lands in a fresh, empty account instead
      # of the one holding their history.
      User.find_by('LOWER(email) = ?', email.to_s.strip.downcase)
    end

    # Not everyone tracks through Home Assistant: plenty of people use the
    # Dawarich phone app or an import, so they never appear in
    # ha_tracked_entities and the map cannot find them. Creating a second,
    # empty account for those people is the one outcome that looks like lost
    # data, so before creating anything, look for the account this add-on would
    # have made for them. It names accounts <name>@dawarich.local, so a Home
    # Assistant user "thomas" lines up with thomas@dawarich.local.
    #
    # Only an exact, single, unclaimed match counts. Anything ambiguous falls
    # through to creating a new account, which is recoverable, rather than
    # signing someone into a stranger's history, which is not.
    #
    # Only the Home Assistant username is matched, never the display name.
    # "Full name" is a field every Home Assistant user can edit on their own
    # profile, so matching on it would let anyone name themselves after another
    # account and be handed it on their next visit. Usernames are set by a Home
    # Assistant admin, which is the whole reason they can be trusted here.
    #
    # The admin account is excluded outright. Its address is configured rather
    # than derived, on a single-user install it holds everything, and it is
    # never the answer to "which Home Assistant user is this?".
    def account_named_after(identity)
      slug = slugify(identity[:name])
      return nil if slug.blank?

      email = "#{slug}@dawarich.local"
      return nil if email == admin_email

      matches = User.where(email: email, provider: nil).limit(2).to_a
      return nil unless matches.one?

      matches.first
    end

    def admin_email
      ENV['ADMIN_EMAIL'].to_s.strip.downcase
    end

    # Built at boot by svc-dawarich from the person entities behind
    # ha_tracked_entities. Read fresh so a restart of the app picks up config
    # changes without a Rails restart.
    def user_map
      raw = File.read(USER_MAP_PATH)
      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : {}
    rescue StandardError
      {}
    end

    def adopt(user, identity)
      # Never move an identity onto a row that already belongs to somebody
      # else: that hands this user the other person's history. The unique index
      # below only catches the case where both rows carry the same uid, which
      # is not the case that hurts.
      if user.uid.present? && user.uid != identity[:id]
        Rails.logger.warn(
          "[ha-ingress-auth] #{user.email} is already linked to a different Home Assistant user, so " \
          "#{describe(identity)} was not signed into it. Showing the login form."
        )
        return nil
      end

      user.update!(provider: PROVIDER, uid: identity[:id])
      Rails.logger.info(
        "[ha-ingress-auth] linked Home Assistant user #{describe(identity)} to existing account #{user.email}"
      )
      user
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.warn(
        "[ha-ingress-auth] Home Assistant user #{describe(identity)} is already linked to another Dawarich " \
        "account, so #{user.email} was left alone. Showing the login form."
      )
      nil
    end

    # Dawarich deletes users softly: the row stays behind with deleted_at set,
    # hidden from every normal query but still holding this identity in the
    # unique index. Without handing it back, deleting an account would strand
    # that Home Assistant user on the login form for good.
    def release_identity_from_deleted_accounts(identity)
      released = User.unscoped
                     .where(provider: PROVIDER, uid: identity[:id])
                     .where.not(deleted_at: nil)
                     .update_all(provider: nil, uid: nil)
      return if released.zero?

      Rails.logger.info(
        "[ha-ingress-auth] released #{describe(identity)} from #{released} deleted account(s)"
      )
    end

    def create(identity)
      email = "#{slug(identity)}@homeassistant.local"
      user, created = Auth::FindOrCreateOauthUser.new(
        provider: PROVIDER,
        provider_label: 'Home Assistant',
        claims: { sub: identity[:id], email: email },
        email_verified: true,
        name_attrs: name_attrs(identity),
        on_email_collision: :raise_only
      ).call

      Rails.logger.info("[ha-ingress-auth] created account #{email} for Home Assistant user #{describe(identity)}") if created
      user
    rescue Auth::FindOrCreateOauthUser::LinkVerificationSent
      # Somebody already owns the address this user's account would get, and it
      # is not theirs to take. Say what to do about it, because the upstream
      # exception name explains nothing to whoever reads the log.
      Rails.logger.warn(
        "[ha-ingress-auth] cannot sign in Home Assistant user #{describe(identity)}: the account #{email} " \
        'already exists and is not linked to them. Sign into that account and change its email, or map this ' \
        'user to the right account with ha_tracked_entities. Showing the login form.'
      )
      nil
    rescue StandardError => e
      Rails.logger.warn("[ha-ingress-auth] could not create an account for #{describe(identity)}: #{e.class}: #{e.message}")
      nil
    end

    def name_attrs(identity)
      full = identity[:display_name].presence || identity[:name].presence
      return {} if full.blank?

      first, last = full.split(' ', 2)
      { first_name: first, last_name: last }.compact
    end

    def slug(identity)
      base = identity[:name].presence || identity[:display_name].presence || identity[:id]
      slugify(base).presence || "ha-#{identity[:id]}"
    end

    def slugify(value)
      ActiveSupport::Inflector.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
    end

    public def describe(identity)
      identity[:display_name].presence || identity[:name].presence || identity[:id]
    end
  end
end

ActiveSupport.on_load(:action_controller_base) do
  prepend_before_action :home_assistant_ingress_sign_in

  private

  def home_assistant_ingress_sign_in
    return unless HomeAssistantIngressAuth.enabled?

    if request.path.match?(%r{/users/sign_out\z})
      # Devise resets the session here, so the opt-out has to live in a cookie.
      cookies[HomeAssistantIngressAuth::OPT_OUT_COOKIE] = {
        value: '1',
        expires: HomeAssistantIngressAuth::OPT_OUT_FOR.from_now,
        httponly: true,
        path: '/'
      }
      return
    end
    return if cookies[HomeAssistantIngressAuth::OPT_OUT_COOKIE].present?

    identity = HomeAssistantIngressAuth.identity(request)
    return if identity.nil?

    signed_in = warden.user(:user)
    return if signed_in && signed_in.provider == HomeAssistantIngressAuth::PROVIDER && signed_in.uid == identity[:id]

    user = HomeAssistantIngressAuth.user_for(identity)

    if user.nil?
      # Home Assistant told us who this is, and it is not whoever the session
      # belongs to. Browsers keep that session, so on a shared device the next
      # person to sign into Home Assistant would be handed the previous one's
      # map and history. Nobody is better than the wrong body.
      if signed_in
        Rails.logger.info(
          "[ha-ingress-auth] signing out #{signed_in.email}: Home Assistant is now #{HomeAssistantIngressAuth.describe(identity)}"
        )
        warden.logout(:user)
      end
      return
    end

    warden.set_user(user, scope: :user) unless signed_in == user
    redirect_to(root_path) if request.path.match?(%r{/users/sign_in\z})
  rescue StandardError => e
    # Never lock anyone out because this failed: fall through to the login form.
    Rails.logger.warn("[ha-ingress-auth] #{e.class}: #{e.message}")
  end
end
