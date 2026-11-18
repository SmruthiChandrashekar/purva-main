# Backend on Azure Container Apps

This runs the **backend API** (`backend/`, `agents/`, `rag/`) on Azure Container Apps.
The website stays on Vercel and Supabase stays as it is. The Render service is not
touched and keeps running until you switch over.

The project shares nothing with other projects in the subscription. Everything is in
its own resource group:

| What | Name |
|------|------|
| Resource group | `purva-main` (Central India, subscription `82aaf9d4-…`) |
| Container registry (Basic) | `purvamain82aaf9d4` |
| Container Apps environment (+ its Log Analytics workspace) | `purva-main-env` |
| Container app | `purva-main` |
| Deploy identity for GitHub | `purva-main-github` |

All names come from `APP_NAME=purva-main` and can be overridden with environment
variables (`APP_NAME`, `RESOURCE_GROUP`, `ACR_NAME`, `ENV_NAME`, `SUBSCRIPTION_ID`).

**How deploys work:** Azure never builds anything (the free trial blocks ACR Tasks).
GitHub Actions builds the image with Docker, pushes it to the project's registry and
points the app at it. The app starts on a placeholder image (nginx on port 8080) until
the first GitHub deploy.

## Supervisor: in Azure Cloud Shell (Bash)

### 1. Get the code

```bash
gh auth login
gh repo clone SmruthiChandrashekar/purva-main
cd purva-main
```

### 2. Copy the settings from Render

Create a Render API key (Render → Account settings → API keys), then:

```bash
read -rs RENDER_API_KEY && export RENDER_API_KEY
```

Paste the key and press Enter. Nothing is shown.

```bash
bash deploy/render-env.sh
```

This writes `.env.azure` (only you can read it, and git ignores it) with every setting of
the Render service `puravankara-grm-backend`. It leaves out `PORT`, `PYTHON_VERSION`,
`RENDER_*`, the one-time admin passwords and empty values, and lists what it left out.
If the service has another name: `RENDER_SERVICE=<name> bash deploy/render-env.sh`.
Settings from Render *environment groups* aren't included. Add those by hand.

Check the file (`nano .env.azure`) before the next step. The names are explained in
`backend/.env.example`.

### 3. Create the Azure resources

```bash
bash deploy/azure.sh
```

To preview first (every command printed, secret values masked, nothing changed):

```bash
DRY_RUN=1 bash deploy/azure.sh
```

It creates whatever is missing (group, registry, environment, app on the placeholder),
stores each setting as a Container Apps **secret**, and lets the app pull from the
registry with its own managed identity (no registry password). At the end it prints the
app's address and says whether it is still on the placeholder.

If Azure answers **InternalServerError** (it sometimes does even when the step worked),
run `bash deploy/azure.sh` again. Every step checks what already exists.

### 4. Let GitHub deploy

```bash
bash deploy/github-setup.sh
```

It creates the identity `purva-main-github`, trusts GitHub Actions runs on `main` of this
repo (both subject forms GitHub uses), and grants it only **Contributor on the
`purva-main` group** and **AcrPush on its registry**. It is safe to rerun.

It prints four `gh variable set …` lines. **Send them to the repo owner.**

## Repo owner (Smruthi)

Run the four lines (Actions variables, not secrets), then start the first deploy:

```bash
gh workflow run azure.yml --repo SmruthiChandrashekar/purva-main
```

Watch it under GitHub → Actions → **Deploy to Azure**. It builds the image, pushes it,
switches the app to it and waits until `https://<app>/health` answers (up to 5 minutes).

After that, every push to `main` that changes the backend (`backend/`, `agents/`, `rag/`,
`requirements.txt`, the Dockerfile) deploys automatically. Frontend-only pushes don't.

### Switching the website over (when ready)

1. In Vercel, set `VITE_API_BASE_URL` to the app's address and redeploy the website.
2. Check `FRONTEND_URL` in the app's settings is the website address (CORS).
3. Then suspend the Render service. Until then both backends work on the same Supabase
   and **both run the SLA monitor**, so escalation emails can go out twice. Keep the
   overlap short.

## Changing a setting later

- **Portal:** Container Apps → `purva-main` → **Settings → Secrets**: change the value,
  then **Revisions and replicas → Restart**. For a new setting, add the secret and then a
  variable that points at it under **Containers → Environment variables**.
- **Or** edit `.env.azure` (`nano .env.azure`) and run `bash deploy/azure.sh`. The image
  stays as it is. The script updates the secrets, **replaces the whole list of environment
  variables** with the file's, and restarts the app. A setting removed from the file
  disappears from the app (its old secret stays, unused).

GitHub deploys never touch settings. They only change the image.

Logs: `az containerapp logs show -n purva-main -g purva-main --follow`

## Size and cost

| Setting | Value | Why |
|---------|-------|-----|
| CPU / memory | 0.25 vCPU / 0.5 GiB | Measured locally with `docker stats`: ~210 MiB in use, about 1% of one core idle. The AI work happens at Groq and Hugging Face. |
| Min replicas | 1 (always on) | The SLA monitor runs inside the app every 5 minutes. If the app slept, escalations would stop. |
| Max replicas | 1 | Phone OTP codes are kept in memory, and a second copy would run the SLA monitor twice. |

Rough monthly cost (list prices; check the Azure pricing calculator for Central India):

| Item | ≈ per month |
|------|-------------|
| Container registry, Basic | US$5 |
| App: one always-on 0.25 vCPU / 0.5 GiB replica | US$6 when mostly idle, up to US$20 if busy all the time (less while the subscription's monthly free grant lasts) |
| Log Analytics (app logs) | under US$1 at this volume (first 5 GB/month free) |
| Environment itself (Consumption) | US$0 |
| **Total** | **≈ US$11–12, at most ≈ US$26** |

## Things to know

- **Local disk is temporary.** What the app writes to its own disk (`debug_error.log`, the
  Chroma index files) is reset on every deploy or restart. That's fine here: complaints,
  files and users are in Supabase, and the policy index ships inside the image.
- **Restarts lose pending phone codes** (users request a new one) and the short login cache.
- The image holds no secrets. `.dockerignore` keeps out `.git`, `.env*`, local databases,
  logs, tests and the frontend.
- Old image tags pile up in the registry (Basic includes 10 GB). Delete old ones in the
  portal now and then.

## Removing it

```bash
az group delete -n purva-main
```

This deletes this project only: app, environment, logs workspace, registry and deploy
identity. Nothing outside the `purva-main` group is affected.
