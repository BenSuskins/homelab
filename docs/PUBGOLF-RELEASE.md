# Pub Golf Go release

> Deploy the Go API and SSE frontend from the same Pub Golf commit.

## Release configuration

Pub Golf PR [#239](https://github.com/BenSuskins/pubgolf/pull/239) merged as
`50041b95b3dd74c4b88a9dd8be830e763cdf393c`. The backend and frontend container tasks
pin the image tags published for that commit. The backend workflow uses the full
commit hash; the frontend workflow uses its first seven characters.

The Docker host runs the backend task before the frontend task. The backend task
pulls both images before changing the API. It checks `/actuator/health` before the
frontend task runs. The frontend task also waits for an HTTP 200 response.
This is a sequential cutover in one Ansible run. Existing
browser tabs must refresh to load the new SSE client.

The backend mounts `{{ base_dir }}/pubgolf-go` at `/data` and sets
`DATABASE_PATH=/data/pubgolf-go.db`. It runs as `puid:pgid`, matching the host data
owner. Go creates its SQLite database on startup. The previous `pubgolf` directory
is not mounted or deleted. The historical database was already deleted by the
operator; this release does not restore historical games or player sessions.

## Cutover

1. Confirm both Pub Golf image-publish workflows pass for the release commit.
2. Choose a window with no active game to preserve. Record the running image digests.
3. Merge the homelab release PR. A push to `main` triggers **Update Homelab**,
   which applies the container tasks through `plays/update.yml`.
4. Confirm that workflow succeeds. Check container logs and database creation.
5. Refresh the browser and create a new game at `https://pubgolf.me`.
6. Join from a second browser and submit a score. Confirm the first browser updates
   without a reload. Reconnect and confirm the current state returns.

## Proxy verification

Traefik routes `api.pubgolf.me/api/v1` to the existing backend host port 8080.
The stream stays under that route. The frontend stays on host port 3003.
This change does not alter the proxy template or introduce response buffering.
Verify the real TLS path after deployment:

```sh
curl --http2 -N -i https://api.pubgolf.me/api/v1/games/GAME_CODE/stream
```

Replace `GAME_CODE` with the new game's code. Confirm HTTP/2, an immediate
`event: game-state`, and heartbeat comments every 15 seconds. Keep the connection
open for at least a minute. Check the Prometheus target and game metrics too.
Local configuration checks do not prove production streaming behavior.

## Rollback

Restore the recorded old backend and frontend image digests together through a
reviewed Ansible change. Restore the old backend data path and configuration if
returning to Kotlin. The deleted historical database is unavailable unless a
separate backup exists; rollback can restore the old application with empty data.
Keep the Go directory so games created after cutover are not deleted. The Kotlin
application cannot read those games.

For the application contract and broader cutover checks, see Pub Golf's
[backend cutover runbook](https://github.com/BenSuskins/pubgolf/blob/main/docs/BACKEND-CUTOVER.md).
