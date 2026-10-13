# Give Net::HTTP back Ruby's native address fallback.
#
# Named z_* so it loads AFTER upstream's dns_cache.rb, which wraps
# Resolv.getaddress and is the other half of this story.
#
# Dawarich bundles the resolv-replace gem. That gem replaces TCPSocket#initialize
# with a version that resolves the hostname through Ruby's pure-Ruby Resolv and
# connects to the ONE address Resolv.getaddress returns:
#
#   def initialize(host, serv, *rest, **kwargs)
#     original_resolv_initialize(IPSocket.getaddress(host), serv, *rest, **kwargs)
#   end
#
# Resolv::DNS#each_address yields AAAA records before A records whenever the
# machine holds any non-loopback, non-link-local IPv6 address. Inside a Home
# Assistant app container that is always true: the Supervisor's `hassio` bridge
# hands out a ULA and installs a default IPv6 route through it, and Supervisor
# enables IPv6 on that network by default (it is also required for Matter, so it
# cannot simply be turned off). The route exists, so the kernel accepts the route
# lookup, but nothing forwards those packets unless the HOST itself has working
# IPv6 egress — and on a typical home network it does not.
#
# The result is that every outbound request resolves to an IPv6 address, connect(2)
# returns ENETUNREACH after about a second, and nothing retries over IPv4, because
# resolv-replace already threw the A records away. Geocoding then fails on every
# point with Geocoder::NetworkError while `curl` to the same host works perfectly,
# which is what makes it look like a Dawarich or provider problem (#11, #23).
#
# /etc/gai.conf cannot help: getaddrinfo is never called on this path. Nor can
# RUBY_TCP_NO_FAST_FALLBACK: Ruby's Happy Eyeballs is never reached either, because
# TCPSocket is handed a literal address rather than a hostname.
#
# Upstream fixed exactly this for SMTP in Freika/dawarich#3619 by letting Net::SMTP
# use the original TCPSocket initializer. This does the same for Net::HTTP, which is
# what every geocoding provider, Immich and PhotoPrism lookup goes through. Ruby then
# resolves the host itself and walks all of its addresses, so a dead IPv6 route falls
# back to IPv4 instead of failing. resolv-replace and Dawarich's Redis-backed DNS
# cache stay in place for every other socket user.
#
# No-op if resolv-replace is ever dropped upstream, and no-op on a working network:
# where IPv6 really does route, the IPv6 address is still tried first and still wins.
Rails.application.config.after_initialize do
  next unless TCPSocket.private_instance_methods.include?(:original_resolv_initialize)

  require 'net/http'

  Net::HTTP.prepend(Module.new do
    private

    def timeouted_connect(conn_addr, conn_port)
      Timeout.timeout(@open_timeout, Net::OpenTimeout) do
        socket = TCPSocket.allocate
        socket.__send__(:original_resolv_initialize, conn_addr, conn_port, @local_host, @local_port)
        socket
      end
    end
  end)
end
