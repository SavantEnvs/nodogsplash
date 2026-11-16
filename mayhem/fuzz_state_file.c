// Fuzzes state_file_import() (src/state_file.c): the JSON state file nodogsplash reloads at start-up.
// The file is staged in $TMPDIR; the client list is flushed after every input so inputs are independent.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "../src/client_list.h"
#include "../src/conf.h"
#include "../src/state_file.h"

/* Globals auth.c would define; auth_change_state() would otherwise drive iptables. Same stub as
 * tests/state_file/test_state_file.c. */
time_t started_time = 0;
unsigned int authenticated_since_start = 0;

int auth_change_state(t_client *client, const unsigned int new_state, const char *reason)
{
	return 0;
}

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	s_config *config = config_get_config();
	config->maxclients = 256;
	config->debuglevel = 0; /* import errors are logged per input */
	client_list_init();
	return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	const char *tmpdir = getenv("TMPDIR");
	char path[4096];
	snprintf(path, sizeof(path), "%s/nds-state-XXXXXX", tmpdir && *tmpdir ? tmpdir : "/tmp");

	int fd = mkstemp(path);
	if (fd < 0)
		abort();
	size_t off = 0;
	while (off < size) {
		ssize_t n = write(fd, data + off, size - off);
		if (n <= 0)
			abort();
		off += n;
	}
	close(fd);

	int rc = state_file_import(path);

	client_list_flush();
	unlink(path);
	return rc == -1 ? -1 : 0; /* -1: not parseable as JSON */
}
