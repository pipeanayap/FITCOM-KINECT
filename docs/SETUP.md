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

### Fotos y eliminación de grupos

Antes de probar estas funciones, aplica las migraciones con `supabase db push`.
`20261025100000_group_photo.sql` agrega `photo_url` a la tabla y a la vista
pública; compilar la app no actualiza la base. Las fotos reutilizan el bucket
`post-images` y sus políticas de la migración del feed.
`20261025110000_group_delete.sql` permite eliminar grupos únicamente a su creador.
Las actividades y publicaciones se conservan sin asociación al grupo.

### Solicitudes e invitaciones a grupos

Aplica `supabase/migrations/20261025120000_group_requests.sql` después de las
migraciones anteriores. Si no tienes la CLI, ejecuta el contenido completo del
archivo en SQL Editor del proyecto de Supabase que usa la app.

- Un usuario solicita ingreso desde el detalle; el creador acepta o rechaza allí.
- El creador usa «Invitar personas» y busca por @usuario; el invitado responde
  en el detalle del grupo desde su notificación.
- Las notificaciones son dentro de la app, sin notificaciones push del sistema.
- Los miembros existentes se conservan. Las solicitudes pendientes no cuentan
  como miembros ni permiten publicar actividades o publicaciones en el grupo.

Comprobación manual con tres cuentas (creador, solicitante e invitado):

1. Solicitar ingreso; verificar el estado pendiente y que no aumente el conteo.
2. Abrir la notificación como creador, aceptar y verificar la membresía.
3. Repetir con rechazo; verificar que no se cree membresía y se pueda solicitar otra vez.
4. Invitar por @usuario; abrir la notificación del invitado y aceptar o rechazar.
5. Verificar que otro usuario no pueda responder solicitudes ajenas ni invitar,
   y que dos respuestas al mismo pendiente no creen membresías duplicadas.
6. Comprobar que un usuario sin membresía no pueda insertarse directamente
   en `community_group_members` usando la API autenticada.

### Quitar integrantes e historias en el perfil

Aplica `supabase/migrations/20261025130000_group_remove_member.sql` en SQL
Editor para habilitar «Eliminar del grupo» en el menú de cada integrante.
Sólo el creador puede quitar integrantes; no puede quitarse a sí mismo.
La persona eliminada puede volver a solicitar ingreso, sujeto a aprobación.

Las historias del perfil reutilizan el visor existente y no necesitan migración:
toca el avatar para verlas, o el botón + para agregar otra. La foto de perfil
se cambia desde «Editar perfil» o desde el menú superior.

Comprobación manual pendiente: quitar un integrante como creador, verificar el
conteo actualizado y que no pueda publicar en el grupo; comprobar que otro
miembro no pueda ejecutar la eliminación. Publicar una historia, abrirla desde
el perfil y verificar que al eliminarla se actualice el aro del avatar.

### Historias con video y cámara

Ejecuta el contenido completo de
`supabase/migrations/20261025140000_story_videos.sql` en SQL Editor antes de
probar. Agrega el tipo de archivo y la duración a las historias y crea el
bucket `story-videos` (MP4, máximo 50 MiB), sin cambiar el bucket de imágenes.
Las historias de foto existentes se conservan.

«Nueva historia» permite elegir foto/video de galería, tomar foto o grabar video.
La cámara requiere permisos de cámara y, para video, micrófono. Las grabaciones
se limitan a 49 segundos; los videos importados de 50 segundos o más se rechazan
sin recortar. La app verifica duración real antes y después de convertir a MP4;
la base valida el rango de duración declarado, no inspecciona el archivo binario.
El visor avanza al terminar el video; las fotos mantienen sus 5 segundos.

Comprobación manual pendiente en un iPhone:

1. Publicar una foto de galería y una capturada; comprobar historias antiguas.
2. Importar videos de 49, 50 y 51 segundos: sólo debe aceptarse el de 49.
3. Grabar con audio, publicar y reproducir desde Inicio y desde el perfil.
4. Denegar cámara o micrófono y comprobar el mensaje y la opción de galería.
5. Cambiar de historia o cerrar el visor y comprobar que se detenga el audio.
6. Reemplazar/cancelar un video y eliminar una historia publicada; verificar que
   se limpien sus archivos temporales y que el borrado use el bucket correcto.

### Chat de grupos

Ejecuta el contenido completo de
`supabase/migrations/20261027100000_group_chat.sql` en SQL Editor (o con
`supabase db push`) antes de probar. Crea `group_messages` con RLS: sólo los
integrantes del grupo leen y escriben (máx. 1000 caracteres), el autor borra
los suyos y el creador del grupo puede borrar cualquiera. También agrega la
tabla a la publicación `supabase_realtime` para recibir mensajes en vivo; si
Realtime no conecta, la app consulta cada 4 segundos.

El chat se abre desde el detalle del grupo, en «Chat del grupo» (sólo
integrantes). Mantén presionado un mensaje para copiarlo o eliminarlo.

Comprobación manual con dos cuentas (ambas integrantes del mismo grupo):

1. Enviar un mensaje desde A y verificar que B lo vea sin recargar.
2. Verificar que una cuenta que no es integrante no vea el botón del chat ni
   pueda leer `group_messages` con la API autenticada.
3. Borrar un mensaje propio; verificar que el creador pueda borrar uno ajeno
   y que un integrante normal no pueda borrar el de otra persona.
4. Salir del grupo y verificar que ya no pueda leer ni escribir.

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
