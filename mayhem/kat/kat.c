// Known-answer probe for the pieces the upstream suite does not cover: the page templater and
// the URL/base64 helpers. mayhem/test.sh compares this output to exact expected lines.
#include <stdio.h>
#include <string.h>

#include "../../src/template.h"

int uh_urldecode(char *buf, int blen, const char *src, int slen);
int uh_urlencode(char *buf, int blen, const char *src, int slen);
int uh_b64decode(char *buf, int blen, const void *src, int slen);

int main(void)
{
	struct template vars[] = {{"name", "Bob"}, {"ver", "5"}, {NULL, NULL}};
	const char *src = "a $name,$unknown;$ver_x $ver!";
	char dst[64];
	char buf[64];
	int n;

	tmpl_parse(vars, dst, sizeof(dst), src, strlen(src));
	printf("tmpl=%s\n", dst);

	memset(dst, 0, sizeof(dst));
	tmpl_parse(vars, dst, 8, src, strlen(src));
	printf("tmpl_trunc=%.8s\n", dst);

	const char *url = "http://a b/c?x=~é";
	n = uh_urlencode(buf, sizeof(buf), url, strlen(url));
	printf("urlencode=%d:%.*s\n", n, n > 0 ? n : 0, buf);
	n = uh_urlencode(buf, 4, "abcdef", 6);
	printf("urlencode_overflow=%d\n", n);

	n = uh_urldecode(buf, sizeof(buf), "a%20b%2Fc", 9);
	printf("urldecode=%d:%.*s\n", n, n > 0 ? n : 0, buf);
	n = uh_urldecode(buf, sizeof(buf), "a%2", 3);
	printf("urldecode_bad=%d\n", n);

	n = uh_b64decode(buf, sizeof(buf), "SGVsbG8h", 8);
	printf("b64decode=%d:%.*s\n", n, n > 0 ? n : 0, buf);
	return 0;
}
