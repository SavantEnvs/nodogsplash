#define _GNU_SOURCE
// Fuzzes tmpl_parse() (src/template.c) the way show_templated_page() in src/http_microhttpd.c
// drives it: the page is the template, the output buffer is page size + TMPLVAR_SIZE, and the
// caller then takes strlen() of the result. Input layout: byte 0 = length N of the request's
// redirect URL, then N bytes of redirect URL (the attacker-controlled variable value), then the page.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../src/template.h"

#define TMPLVAR_SIZE 4096 /* same value as src/http_microhttpd.c */

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	if (size < 1)
		return -1;

	size_t redir_len = data[0];
	if (redir_len > size - 1)
		redir_len = size - 1;
	const uint8_t *page = data + 1 + redir_len;
	size_t page_len = size - 1 - redir_len;

	char *redir = malloc(redir_len + 1);
	memcpy(redir, data + 1, redir_len);
	redir[redir_len] = '\0';

	char *authtarget = NULL;
	if (asprintf(&authtarget, "http://%s/%s/?tok=%s&amp;redir=%s",
		     "192.168.1.1:2050", "nodogsplash_auth", "0a1b2c3d", redir) < 0)
		abort();

	struct template vars[] = {
		{"authaction", "http://192.168.1.1:2050/nodogsplash_auth/"},
		{"denyaction", "http://192.168.1.1:2050/nodogsplash_deny/"},
		{"authtarget", authtarget},
		{"clientip", "192.168.1.23"},
		{"clientmac", "00:16:3e:d8:29:6e"},
		{"clientupload", "918"},
		{"clientdownload", "1586"},
		{"gatewaymac", "00:11:22:33:44:55"},
		{"gatewayname", "NoDogSplash"},
		{"maxclients", "250"},
		{"nclients", "3"},
		{"redir", redir},
		{"tok", "0a1b2c3d"},
		{"token", "0a1b2c3d"},
		{"uptime", "0d 1h 2m 3s"},
		{"version", "5.0.0"},
		{NULL, NULL}
	};

	char *src = malloc(page_len ? page_len : 1);
	memcpy(src, page, page_len);
	size_t dst_len = page_len + TMPLVAR_SIZE;
	char *dst = calloc(dst_len, 1);

	tmpl_parse(vars, dst, dst_len, src, page_len);
	volatile size_t out_len = strlen(dst);
	(void)out_len;

	free(dst);
	free(src);
	free(authtarget);
	free(redir);
	return 0;
}
