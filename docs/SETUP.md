# FITCOM (Kinect) — cómo correr el proyecto en local

App de iOS en SwiftUI con [xtool](https://github.com/xtool-org/xtool) (permite
compilar e instalar apps de iOS desde Linux/WSL sin Xcode), respaldada por
[Supabase](https://supabase.com) (Postgres + autenticación + API).

## Requisitos

- `xtool` instalado y con sesión de Apple iniciada: `xtool auth status`.
- El SDK de iOS de xtool instalado: `xtool sdk status`.
- [Supabase CLI](https://supabase.com/docs/guides/cli) — ya está en
  `~/.local/bin/supabase` en este entorno de desarrollo.
- Una cuenta de Supabase con un proyecto creado para FITCOM.

## Backend (Supabase)

1. Inicia sesión una sola vez: `supabase login`.
2. Vincula este repo con tu proyecto (pide el *project ref*, está en la URL
   del dashboard): `supabase link --project-ref <ref>`.
3. Aplica el esquema: `supabase db push`. Esto corre todo lo que hay en
   `supabase/migrations/`.
4. En Settings → API del dashboard, copia la **Project URL** y la
   **anon public key**.
5. Copia la plantilla de claves y pon ahí esos dos valores:
   ```bash
   cp Sources/Kinect/Supabase/Secrets.swift.example Sources/Kinect/Supabase/Secrets.swift
   ```
   `Secrets.swift` está en `.gitignore`: cada quien usa las suyas, nunca se
   sube al repositorio.

### Datos de prueba

`supabase/seed.sql` crea 3 usuarios y un par de actividades de ejemplo.
Sólo sirve para una base de datos de pruebas (crea filas directo en
`auth.users`, algo que no se hace así en producción):

```bash
supabase db reset        # si corres Supabase en local (supabase start)
# o, contra el proyecto remoto, directo con psql:
psql "$(supabase db diff --help >/dev/null; supabase status -o env | grep DB_URL | cut -d= -f2-)" -f supabase/seed.sql
```

> Para desarrollo 100% local (`supabase start`) hace falta Docker con
> integración a WSL2. En este entorno no está disponible, así que por ahora
> se trabaja contra un proyecto remoto de Supabase.

## App de iOS

```bash
xtool dev            # compila e instala en el iPhone conectado
xtool dev build       # sólo compila
xtool dev build --ipa # genera un .ipa para instalar con Sideloadly u otra app
```

El iPhone se conecta por USB vía `usbipd` (WSL2). Ver [[wsl-iphone-usbmuxd-patch]]
si la instalación falla con `opTimeout`: hay un `usbmuxd` parcheado instalado
para que funcione sobre WSL2.

## Estructura del repo

```
Sources/Kinect/           # app de iOS (SwiftUI)
  Supabase/                # cliente de Supabase y claves locales
supabase/
  migrations/              # esquema de la base de datos, versionado
  seed.sql                 # datos de prueba (sólo desarrollo)
docs/                     # esta documentación
```
