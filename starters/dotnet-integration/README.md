# .NET integration-test starter (verify `integration`)

A starting point for the 3–5 critical journeys `verify` runs for `stack: dotnet-service` (and for a
library that talks to Postgres, Redis or another outside system). Copy `Api.IntegrationTests/` next
to your API, rename it (for example `MyService.IntegrationTests`), then replace `/items` with your
API's real endpoints.

## Set up
1. Copy the folder and point its `<ProjectReference>` at your API project. Add it to your solution
   (`dotnet sln add …`): `verify` only runs test projects that are in the solution.
2. Make `Program` visible to the tests: add `public partial class Program { }` at the end of
   `Program.cs` (top-level statements make it internal otherwise).
3. Your API reads its connection string from `ConnectionStrings:Default` (change the key in
   `ApiFactory` if yours differs) and uses JwtBearer authentication. `ApiFactory` swaps the identity
   provider for a test-only key, so no real provider is ever called.
4. `/health` must be liveness only (no database check), and the image must start without its
   database: `verify` also runs your Docker image and probes `/health`.
5. Run it: `dotnet test` (Docker must be running: Testcontainers starts `postgres:17`).

## What `verify` does with it
- It references `Testcontainers`, so `verify` runs it in the hosted `integration` job, which has
  Docker. Other test projects keep running in the `test` step.
- A test project whose config (`appsettings*.json`, `*.runsettings`, …) holds a connection string
  to a real server is **never run**, and `verify` names it. Use Testcontainers or `localhost`
  values, and delete real credentials from the repository.
- Pin container images to production's version (`postgres:17`, `redis:7`, …), never `latest`.

## Journeys to keep
- `/health` returns 200.
- One write-then-read round trip through the API and the database.
- An invalid token returns 401; a token signed with the test-only key is accepted.
- 1–2 of your main endpoints (the commented template in `JourneyTests.cs`).
