# Backend on Azure Container Apps

This runs the **backend API** (`backend/`, `agents/`, `rag/`) on Azure Container Apps.
The website stays on Vercel and Supabase stays as it is. The Render service is not
touched and keeps running until you switch over.

The project has its own resource group, registry, app, settings and deploy identity.
Only the **Container Apps environment** is shared, because the subscription (a free trial)
allows just one environment in total, and another project already has it:

| What | Name | Whose |
|------|------|-------|
| Resource group | `purva-main` (Central India, subscription `82aaf9d4-…`) | this project |
| Container registry (Basic) | `purvamain82aaf9d4` | this project |
| Container app (with its own secrets and settings) | `purva-main` | this project |
| Deploy identity for GitHub | `purva-main-github` | this project |
| Container Apps environment | `purva-bot-env` in group `purva-bot` | **shared**, only read, never changed |

All names come from `APP_NAME=purva-main` and can be overridden with environment
variables (`APP_NAME`, `RESOURCE_GROUP`, `ACR_NAME`, `SUBSCRIPTION_ID`, and for the
shared environment `ENV_NAME`, `ENV_RESOURCE_GROUP`). Don't set `LOCATION`: the app runs
where the shared environment is (Central India).

## What is shared, and why settings can't clash

**Settings belong to the app, not the environment.** Every secret and environment
variable (`SUPABASE_URL`, `GROQ_API_KEY`, …) is stored on the `purva-main` app itself.
Another app in the same environment can use the same names with different values: neither
app can see or overwrite the other's. So **no setting has been renamed**: the names
are exactly the ones in `backend/.env.example` and on Render, and the backend code is
unchanged.

| Shared through the environment | Effect on this project |
|-------------------------------|------------------------|
| App names must be unique in the environment | `azure.sh` checks that no other project already has an app called `purva-main`, and stops if one does (rerun with `APP_NAME=<other>`). |
| Web address ending (`<app>.<env-domain>.centralindia.azurecontainerapps.io`) | Each app gets its own address from its own name. |
| The environment's Log Analytics workspace (in `purva-bot`) | This app's console logs go there too. People with access to `purva-bot` can read them, and the (small) log cost is billed there. The backend doesn't log secret values. |
| The environment itself | If the other project deletes or recreates `purva-bot-env`, this app goes down with it. Agree with them before anyone changes it. |

**Not shared:** secrets, environment variables, the image registry, the app's own pull
identity, the deploy identity and its permissions, scaling, and the bill for the app itself.

**The one permission outside this project's group:** GitHub's deploy identity gets a
custom role on `purva-bot-env` with only `managedEnvironments/read` and
`managedEnvironments/join/action`. Azure checks that permission every time an app in the
environment is updated. It can't change the environment or any other app in it.

**The script's own settings changed, not the app's:** `azure.sh` and `github-setup.sh` now
read `ENV_NAME` (default `purva-bot-env`) and `ENV_RESOURCE_GROUP` (default `purva-bot`)
instead of creating `purva-main-env`.

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

It creates whatever is missing (group, registry, and the app on the placeholder inside the
shared environment), stores each setting as a Container Apps **secret** on the app, and
lets the app pull from the registry with its own managed identity (no registry password).
At the end it prints the app's address and says whether it is still on the placeholder.

If Azure answers **InternalServerError** (it sometimes does even when the step worked),
run `bash deploy/azure.sh` again. Every step checks what already exists.

If it lists **unused log workspaces** in `purva-main` (left by earlier attempts to create a
separate environment), run the delete lines it prints. They're empty and not needed.

### 4. Let GitHub deploy

```bash
bash deploy/github-setup.sh
```

It creates the identity `purva-main-github`, trusts GitHub Actions runs on `main` of this
repo (both subject forms GitHub uses), and grants it only:
- **Contributor** on the `purva-main` group,
- **AcrPush** on its registry,
- on the shared `purva-bot-env` only: a custom role, **Container Apps environment join
  (purva-bot-env)**, with `read` + `join/action`. Updating an app in that environment
  needs it, and it can't change the environment or other apps.

It is safe to rerun.

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
| Log Analytics (app logs) | under US$1 at this volume, billed in the shared environment's workspace (`purva-bot`) |
| Environment (shared, Consumption) | US$0 |
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

This deletes this project only: app, registry and deploy identity. The shared environment
`purva-bot-env` and the other project's app stay as they are. Also remove this project's
permission on the shared environment (the role assignment goes away with the identity;
the role definition is left over):

```bash
az role definition delete --name "Container Apps environment join (purva-bot-env)"
```
