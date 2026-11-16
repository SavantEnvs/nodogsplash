// AFL file-input target for the config file parser (config_read() in src/conf.c). The parser
// calls exit(1) on every malformed directive, so it needs one process per input.
// Usage: fuzz_conf <config file>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include "../src/conf.h"

/* format_time() lives in util.c, which pulls in the whole daemon; same stub as tests/conf/test_conf.c. */
char *format_time(time_t t, char *buf)
{
	strftime(buf, 64, "%a %b %d %H:%M:%S %Y", localtime(&t));
	return buf;
}

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: %s <config file>\n", argv[0]);
		return 2;
	}
	config_init();
	config_read(argv[1]);
	return 0;
}
