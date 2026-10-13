"""Integration regression test against an actual Home Assistant ingress URL.

DAWARICH_INGRESS_URL is the app's ingress base URL. An authenticated ingress
session can be supplied in DAWARICH_INGRESS_COOKIE, without command-line secrets.
"""
import json
import os
import re
import unittest
import urllib.parse
import urllib.request


class MapLibreIngressTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base_url = os.environ.get('DAWARICH_INGRESS_URL', '').rstrip('/')
        if not cls.base_url:
            raise unittest.SkipTest('DAWARICH_INGRESS_URL is required for the integration test')
        cls.headers = {}
        cookie = os.environ.get('DAWARICH_INGRESS_COOKIE')
        if cookie:
            cls.headers['Cookie'] = 'ingress_session=' + cookie
        with cls.fetch(cls.base_url + '/users/sign_in') as response:
            html = response.read().decode('utf-8')
        script = re.search(r'<script\b[^>]*type=[\"\']importmap[\"\'][^>]*>(.*?)</script>',
                           html, re.DOTALL | re.IGNORECASE)
        if script is None:
            raise AssertionError('Dawarich importmap not found in the ingress response')
        cls.entry = json.loads(script.group(1))['imports']['maplibre-gl']
        cls.module_url = urllib.parse.urljoin(cls.base_url + '/', cls.entry)

    @classmethod
    def fetch(cls, url):
        return urllib.request.urlopen(urllib.request.Request(url, headers=cls.headers), timeout=30)

    def test_importmap_keeps_the_ingress_prefix(self):
        prefix = urllib.parse.urlparse(self.base_url).path.rstrip('/') + '/maplibre/'
        self.assertTrue(urllib.parse.urlparse(self.module_url).path.startswith(prefix),
                        'MapLibre importmap URL escapes Home Assistant ingress')

    def test_entrypoint_is_served_as_javascript(self):
        with self.fetch(self.module_url) as response:
            self.assertEqual(response.status, 200)
            self.assertIn(response.headers.get_content_type(),
                          ('application/javascript', 'text/javascript'))

    def test_relative_shared_module_and_worker_are_javascript(self):
        for filename in ('maplibre-gl-shared.mjs', 'maplibre-gl-worker.mjs'):
            with self.subTest(module=filename):
                url = urllib.parse.urljoin(self.module_url, filename)
                with self.fetch(url) as response:
                    self.assertEqual(response.status, 200)
                    self.assertIn(response.headers.get_content_type(),
                                  ('application/javascript', 'text/javascript'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
