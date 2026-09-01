# Rhino 8 sous Wine — notes techniques

Procédure vérifiée commande par commande sur deux machines, avec les pièges qui coûtent des heures, les points où les deux installations se contredisent, et une liste honnête de ce qui ne fonctionne pas.

| | Machine A | Machine B |
|---|---|---|
| Système | Ubuntu 26.04 « Resolute » | Linux Mint 22.3 (base noble) |
| Session | GNOME / XWayland | X11 / Cinnamon |
| GPU | NVIDIA GTX 1080 · 580.173.02 | Intel HD 630 + GTX 1060 (Optimus) |
| CPU / RAM | Threadripper 1900X · 98 GB | i7-7700HQ · 31 GB |
| Wine | 11.15 staging | 11.16 staging |

---

## Prérequis

- Une distribution basée sur Ubuntu 24.04 (noble) ou plus récente.
- Une session X11 ou XWayland. Wayland natif n'a pas été testé.
- Droits sudo, 12 Go libres dans `$HOME`, 8 Go de RAM au minimum (16 Go réalistes).
- Une connexion internet stable pendant toute l'installation : l'exécutable officiel est un téléchargeur.
- `$HOME/.local/bin` présent dans le `PATH`.

## Procédure

### 1. Identifier le nom de code APT

```bash
. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}"
echo "session: ${XDG_SESSION_TYPE:-inconnue}"
```

Le dépôt WineHQ est indexé par nom de code *Ubuntu*, pas par celui de votre distribution dérivée. Sur Mint 22.3, `lsb_release -sc` renvoie « zena » et l'URL WineHQ répond 404 ; il faut lire `UBUNTU_CODENAME`, qui vaut « noble ». Notez aussi votre session graphique : tout ceci a été validé en X11 et en XWayland, jamais en Wayland natif.

> **Vérifier** — `curl -o /dev/null -w '%{http_code}\n' https://dl.winehq.org/wine-builds/ubuntu/dists/$CODENAME/` doit répondre 200. S'il répond 404, vous avez pris le nom de code de la distribution dérivée.

### 2. Vérifier matériel, RAM et espace disque

```bash
free -h
df -h "$HOME"
lspci -nn | grep -iE 'vga|3d'
```

Mesuré à l'arrivée : préfixe 7,0 Go (dont 3,7 Go pour `drive_c/windows` à cause des assemblages .NET Framework 4.8, 1,3 Go pour Rhino, 908 Mo pour WebView2), plus 636 Mo d'installeur téléchargé. Rhino occupe environ 1,2 Go de mémoire avec un simple cube. Le résultat de `lspci` décide si les étapes Optimus vous concernent.

> **Vérifier** — Au moins 12 Go libres dans `$HOME` et 8 Go de RAM (16 Go réalistes). Deux contrôleurs graphiques listés = cas Optimus.

### 3. Activer l'architecture i386

```bash
sudo dpkg --add-architecture i386
dpkg --print-foreign-architectures
```

Étape **bloquante** et absente de nos notes initiales : `wine-staging` dépend en dur de `wine-staging-i386` à la même version. Sans l'architecture 32 bits, l'installation échoue sur des dépendances introuvables. Vérifiez aussi que *universe* et *multiverse* sont actifs — c'est le cas par défaut sur Mint et Ubuntu de bureau, pas sur une installation minimale.

> **Vérifier** — La commande doit lister `i386`.

### 4. Ajouter la clé et le dépôt WineHQ

```bash
. /etc/os-release && CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
sudo wget -NP /etc/apt/sources.list.d/ "https://dl.winehq.org/wine-builds/ubuntu/dists/$CODENAME/winehq-$CODENAME.sources"
gpg --show-keys --with-fingerprint /etc/apt/keyrings/winehq-archive.key
```

Le nom du fichier de clé n'est pas libre : le `.sources` publié par WineHQ contient `Signed-By: /etc/apt/keyrings/winehq-archive.key`. Gardez la clé en **armure ASCII** — ne faites *pas* `gpg --dearmor`, contrairement à beaucoup de tutoriels. Sur les distributions à apt 3.x (Ubuntu 25.10 et suivantes) le nom attendu peut être en `.asc` : lisez le champ `Signed-By` du fichier téléchargé et nommez la clé en conséquence.

> **Vérifier** — L'empreinte doit être `D43F 6401 4536 9C51 D786 DDEA 76F1 A20F F987 672F`, uid « WineHQ packages ». **Cas vérifié sur Ubuntu 26.04** (apt 3.x) : la clé en `.key` est ignorée *en silence*, le dépôt passe « non signé » avec `NO_PUBKEY 76F1A20FF987672F`. Il faut la nommer `.asc` et corriger le fichier : `sudo sed -i 's|winehq-archive\.key|winehq-archive.asc|' /etc/apt/sources.list.d/winehq-*.sources`

### 5. Installer winehq-staging et vérifier qui répond

```bash
sudo apt update
sudo apt install --install-recommends winehq-staging
wine --version
readlink -f "$(command -v wine)"
dpkg -S "$(command -v wine)"
```

`--install-recommends` n'est pas décoratif : il tire libgnutls (TLS, donc activation de licence), libglu1-mesa, GTK, CUPS, Kerberos et toute la série libx*. Sans lui l'installation est dégradée. On choisit *staging* car la branche stable plafonnait à 11.0 quand staging était à 11.16. Point important : les paquets Wine 9.0 de la distribution peuvent rester installés à côté — d'où la vérification ci-dessous, la seule qui prouve que le bon Wine répond.

> **Vérifier** — `readlink -f` doit pointer sur `/opt/wine-staging/bin/wine` et `dpkg -S` répondre `winehq-staging`. Aucun binaire `wine64` n'existe avec winehq-staging : ne l'utilisez jamais dans vos scripts.

### 6. Installer un winetricks récent

```bash
mkdir -p "$HOME/.local/bin"
wget -O "$HOME/.local/bin/winetricks" https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x "$HOME/.local/bin/winetricks"
hash -r; winetricks --version
```

Le winetricks des dépôts est en 20240105, soit deux ans de retard sur celui employé ici. Un winetricks de 2024 ignore les URL actuelles et les contournements des bogues Wine 53925 et 58921, appliqués automatiquement par le verbe `webview2`.

> **Vérifier** — `command -v winetricks` doit renvoyer le chemin dans `~/.local/bin`, pas `/usr/bin`.

### 7. Créer le préfixe 64 bits

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
export WINEARCH=win64
WINEDLLOVERRIDES="mscoree=d;mshtml=d" wineboot --init
grep -am1 '#arch' "$WINEPREFIX/system.reg"
```

Choisissez un chemin **sans espace ni nom d'utilisateur** : techniquement les espaces fonctionnent, mais chaque commande copiée devient un piège de guillemets. Les surcharges `mscoree=d;mshtml=d` empêchent Wine-Mono de s'installer — Rhino embarque son propre .NET 8. À savoir : Wine relie `Documents`, `Bureau` et `Téléchargements` du préfixe à vos *vrais* dossiers Linux, et le dossier utilisateur porte votre login.

> **Vérifier** — `#arch=win64` attendu. Un préfixe 32 bits ne peut pas installer `rhino.msi`, qui est x64.

### 8. Installer les composants Windows

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
winetricks -q corefonts d3dcompiler_47 vcrun2022 dotnet48
cat "$WINEPREFIX/winetricks.log"
```

`dotnet48` est **obligatoire** et c'est le gros morceau : le MSI de Rhino exécute des actions personnalisées managées (WiX/DTF) qui réclament un CLR .NET Framework *en plus* du .NET 8 embarqué. Sans lui, l'installation meurt sur `0x80070643`. Ne vous alarmez pas si le journal contient des verbes non demandés : `dotnet48` appelle `remove_mono` puis `dotnet40`, qui bascule temporairement en Windows XP.

> **Vérifier** — Le journal doit contenir corefonts, d3dcompiler_47, vcrun2022 et dotnet48. `drive_c/windows/mono` doit être **absent**.

### 9. Remettre le préfixe en Windows 10

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
wine winecfg /v win10
wine reg query "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentBuild
```

**Le piège central de toute la procédure.** Dans winetricks, `load_dotnet48()` se termine par `w_set_winver win7` *sans restauration* — contrairement à `load_dotnet40()` qui encadre son changement. Le préfixe reste donc en Windows 7, et l'installation de Rhino échoue ensuite silencieusement. `wine winecfg /v` sans argument affiche la version courante : c'est le contrôle ; avec `win10`, c'est la correction.

> **Vérifier** — **Vérifié à l'exécution :** `wine winecfg /v` sans argument n'affiche *rien* sur Wine 11.16 — ne l'utilisez pas comme contrôle. La seule source fiable est le registre : `CurrentBuild` doit valoir **19045** (Windows 10) et non 7601 (Windows 7). **Attention** : `CurrentVersion` vaut 6.3 dans les deux cas — le vrai Windows 10 aussi.

### 10. Installer WebView2 avant l'installeur Rhino

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
winetricks -q webview2
wine reg query "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentBuild
ls "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/"
```

Nos notes d'origine plaçaient WebView2 *après* Rhino : c'est une erreur d'ordre. Le journal de l'installeur montre l'arrêt exactement sur `Redist_MSWebView2_Standalone` (erreur `0x80040902`), avant même les runtimes .NET. WebView2 sert aussi à la fenêtre de licence, qui reste blanche sans lui. Effet de bord normal : winetricks pose une surcharge *par application* `msedgewebview2.exe = win7` — ne la supprimez pas, elle ne change pas la version globale.

> **Vérifier** — Le dossier de version existe, et `CurrentBuild` vaut toujours 19045. Le binaire `msedgewebview2.exe` pèse environ 4,6 Mo — ne testez pas la seule présence du dossier, qui apparaît dès le début de l'extraction.

### 11. Obtenir l'installeur officiel

```bash
ls -lh ~/Téléchargements/rhino_en-us_*.exe 2>/dev/null || ls -lh ~/Downloads/rhino_en-us_*.exe
```

Téléchargez uniquement depuis **rhino3d.com**, avec un compte McNeel. Le fichier suit le motif `rhino_en-us_<VERSION>.exe`, environ 636 Mo. Point jamais dit et pourtant décisif : ce `.exe` est un **téléchargeur**. Il va chercher vcredist, WebView2, le Desktop Runtime et ASP.NET Core sur `files.mcneel.com` pendant son exécution. Une installation hors ligne est impossible. Rien ici ne contourne la licence.

> **Vérifier** — Taille de l'ordre de 600–700 Mo, et accès à `files.mcneel.com` disponible.

### 12. Lancer l'installeur, puis lire son journal

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
wine ~/Téléchargements/rhino_en-us_*.exe -passive -norestart
LOG=$(ls -t "$WINEPREFIX/drive_c/users/$USER/AppData/Local/Temp/Rhino_8_"*.log | head -1); echo "$LOG"
grep -E 'i301:|i319:|i338:|i399:|i007:' "$LOG" | tail -40
```

Avec les étapes 9 et 10 faites, l'installeur devrait aller au bout tout seul — c'est ce qui s'est produit sur la machine Ubuntu. Sur la machine Mint il avait échoué, mais *parce que* ces deux étapes manquaient. Ne concluez rien sans lire le journal : c'est lui qui dit si les MSI ont été appliqués.

> **Vérifier** — Succès : pas d'`Error 0x…` sur un paquet et `Program Files/Rhino 8/System/Rhino.exe` présent — passez à l'étape 14. Échec : un `i319 … result: 0x…` non nul — passez à l'étape 13.

### 13. Repli : installation manuelle sans coder de GUID

```bash
export PC="$WINEPREFIX/drive_c/ProgramData/Package Cache"
find "$PC" -type f \( -iname '*.msi' -o -iname '*.exe' \) -printf '%10s  %P\n' | sort -k2
find_one() { find "$PC" -type f "$@" -print -quit; }
DESKTOP_RT=$(find_one -path '*/redist/*' -iname 'windowsdesktop-runtime*win-x64.exe')
ASPNET_RT=$(find_one -path '*/redist/*' -iname 'aspnetcore*x64.exe')
RHIEXEC_MSI=$(find_one -iname 'rhiexec.msi'); RHINO_MSI=$(find_one -iname 'rhino.msi')
for v in DESKTOP_RT ASPNET_RT RHIEXEC_MSI RHINO_MSI; do f=${!v}; printf "%-12s %12s  %s\n" "$v" "$(stat -c %s "$f")" "$f"; done
wine "$DESKTOP_RT" /quiet /norestart && wine "$ASPNET_RT" /quiet /norestart
wine msiexec /i "$RHIEXEC_MSI" /qn /l*v 'C:\rhiexec.log'
wine msiexec /i "$RHINO_MSI" /qn /l*v 'C:\rhino_msi.log'
```

Deux conventions de nommage cohabitent dans le cache : `{GUID}vVERSION` pour les MSI Rhino, mais une **empreinte SHA-1** sans accolades pour les runtimes .NET. Ne codez donc aucun identifiant en dur, ils changent à chaque version. Le filtre `-path '*/redist/*'` est **essentiel** : sans lui, `find` renvoie d'abord une copie du moteur d'installation de 622 Ko au lieu du vrai redistribuable de 58 Mo, et l'installation « réussit » sans rien installer. Contrôlez toujours les tailles avant d'exécuter.

> **Vérifier** — Ordres de grandeur attendus : rhino.msi ≈ 550 Mo, rhiexec.msi ≈ 1 Mo, windowsdesktop ≈ 58 Mo, aspnetcore ≈ 10 Mo. Ensuite `grep -a 'VersionNT' C:\rhino_msi.log` doit donner **603** et non 601.

### 14. Vérifier ce qui est réellement installé

```bash
wine reg query 'HKLM\Software\McNeel\Rhinoceros\8.0\Install' /v Version
ls -l "$WINEPREFIX/drive_c/Program Files/Rhino 8/System/Rhino.exe"
ls "$WINEPREFIX/drive_c/Program Files/dotnet/shared/"*
```

Bilan avant de toucher au lanceur. Attendu : Rhino 8, Rhino Installer Engine, .NET Framework 4.8, les runtimes .NET 8 (Core, Desktop, ASP.NET), WebView2, et les VC++ 2015-2022 et 2013.

> **Vérifier** — Le registre renvoie le numéro de build ; `dotnet/shared` contient les trois sous-dossiers en 8.0.x.

### 15. Optimus : décider si les variables PRIME servent

```bash
glxinfo -B | grep 'OpenGL renderer'
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo -B | grep 'OpenGL renderer'
```

Test décisif et instantané, sans lancer Rhino. Sur la machine de référence : `Mesa Intel HD Graphics 630` sans variables, `NVIDIA GeForce GTX 1060` avec. Si les deux lignes sont **identiques**, vous n'êtes pas en Optimus : n'activez pas le bloc NVIDIA. Ces variables ne cassent rien ailleurs — libglvnd retombe silencieusement sur Mesa — mais elles réveillent la carte dédiée à chaque lancement sur un portable.

> **Vérifier** — Les deux lignes doivent différer pour que le bloc NVIDIA ait un sens.

### 16. Installer le script de lancement

```bash
# voir le script complet plus bas / see the full script below
chmod +x "$HOME/.local/bin/rhino8.sh"
"$HOME/.local/bin/rhino8.sh"
```

Trois différences avec notre script d'origine, toutes motivées par des mesures. Le bloc NVIDIA est **commenté** et isolé. `__VK_LAYER_NV_optimus` a été retirée : sans effet. Et surtout, la conversion de chemin par `winepath -w` est ajoutée — vérifié par lancements comparatifs, avec un chemin Unix Rhino ouvre « Untitled », avec le chemin converti il ouvre bien le fichier.

> **Vérifier** — Rhino démarre. Avec le bloc NVIDIA actif, `nvidia-smi | grep -i rhino` doit montrer une consommation réelle (107 Mio mesurés) ; environ 1 Mio signifie que le processus ne dessine pas sur le GPU dédié.

### 17. Entrée de menu et association .3dm

```bash
desktop-file-validate "$HOME/.local/share/applications/rhino8-wine.desktop"
update-desktop-database "$HOME/.local/share/applications"
xdg-mime default rhino8-wine.desktop application/x-wine-extension-3dm
gtk-launch rhino8-wine
```

Deux défauts réels de notre fichier d'origine sont corrigés ici. Sans ligne `MimeType=` ni association explicite, un double-clic sur un `.3dm` passe par le raccourci généré automatiquement par winemenubuilder, qui ne définit que `WINEPREFIX` : mesuré, ce Rhino-là n'occupe que 1 Mio sur la carte NVIDIA contre 107 Mio via le lanceur — **l'accélération est perdue**. Et `%f` transmet un chemin Unix, que Rhino ignore : il ne fonctionne qu'avec la conversion ajoutée à l'étape 16.

> **Vérifier** — `desktop-file-validate` ne doit rien afficher, et un double-clic sur un `.3dm` doit ouvrir le fichier — titre de fenêtre à l'appui.

### 18. Premier lancement et licence

```bash
"$HOME/.local/bin/rhino8.sh" 2>&1 | tee /tmp/rhino-first-run.log
```

L'activation Cloud Zoo passe par WebView2 et votre navigateur : c'est ici que l'étape 10 est payante. Messages **attendus**, qui ne signalent aucun problème : `libEGL warning: … driver (null)` et `egl: failed to create dri2 screen` à chaque lancement, et `Failed to unregister class Chrome_WidgetWin_0. Error = 1412` à la fermeture.

> **Vérifier** — Rhino ouvre sa fenêtre principale et le titre indique l'état de licence.

### 19. Rafraîchissement des viewports

```bash
# -> "Two machines, two remedies" / "Deux machines, deux remedes"
```

C'est le point où les deux machines **divergent**, et où il ne faut surtout pas fusionner les recettes. Lisez la section dédiée avant d'appliquer quoi que ce soit.

> **Vérifier** — Voir la section comparative.

### 20. Arrêter proprement entre deux essais

```bash
pkill -9 -f 'Rhin[o]\.exe'
pkill -9 -f 'wineserve[r]'
pgrep -af 'wine|Rhino'
```

Les crochets ne sont pas une coquetterie : `pkill -9 -f "Rhino.exe"` tue le terminal qui exécute la commande, car sa propre ligne de commande contient le motif recherché. Par ailleurs `wineserver -k` n'a pas suffi à arrêter Rhino dans nos essais. La fermeture laisse des processus orphelins qui s'accumulent et rendent les lancements suivants erratiques.

> **Vérifier** — `pgrep` ne doit plus rien renvoyer avant le lancement suivant.

### 21. Hygiène avant de partager

```bash
grep -rInE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+|/home/[a-z]+' . --include='*.xml' --include='*.sh' --include='*.py'
```

À lire **avant** de publier un dépôt, une sauvegarde ou une capture. Ne partagez jamais le préfixe ni le dossier *License Manager* : sous Wine le DPAPI est factice, et `cloudzoo.json` contient littéralement la chaîne base64 de « Wine Crypt32 ok ». **Le jeton d'authentification n'est pas protégé.** Le fichier de réglages de Rhino contient par ailleurs l'adresse e-mail du compte et des chemins nominatifs.

> **Vérifier** — Le grep ne doit plus remonter aucune adresse e-mail ni `/home/LOGIN` dans ce que vous publiez.

## Les deux fichiers à créer

`~/.local/bin/rhino8.sh`

```bash
#!/usr/bin/env bash
# Lance Rhino 8 sous Wine.
set -u
export WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/rhino8}"
export WINEDEBUG=-all

# --- BLOC OPTIONNEL : portable Optimus Intel + NVIDIA -----------------
# Ne decommentez que si l'etape 15 montre deux renderers differents.
#export __NV_PRIME_RENDER_OFFLOAD=1
#export __GLX_VENDOR_LIBRARY_NAME=nvidia
# Desactive l'attente du balayage vertical : palliatif du rafraichissement
# fige, mais peut provoquer du dechirement d'image.
#export __GL_SYNC_TO_VBLANK=0   # pilote NVIDIA
#export vblank_mode=0           # equivalent Mesa

# Rhino n'accepte pas les chemins Unix : conversion obligatoire.
args=()
for f in "$@"; do
  if [ -e "$f" ]; then args+=("$(winepath -w "$f" 2>/dev/null || echo "$f")")
  else args+=("$f"); fi
done
exec wine "C:\Program Files\Rhino 8\System\Rhino.exe" ${args[@]+"${args[@]}"}
```

`~/.local/share/applications/rhino8-wine.desktop`

```ini
[Desktop Entry]
Type=Application
Name=Rhinoceros 8 (Wine)
Exec=/home/VOTRE_LOGIN/.local/bin/rhino8.sh %f
Icon=/home/VOTRE_LOGIN/.local/share/icons/rhino8.ico
Terminal=false
Categories=Graphics;3DGraphics;
MimeType=application/x-wine-extension-3dm;
StartupWMClass=rhino.exe
```

## Deux machines, deux remèdes

Les deux installations divergent sur cinq points, et fusionner leurs recettes produirait des instructions contradictoires.

| | Ubuntu 26.04 · XWayland · GTX 1080 | Mint 22.3 · X11 · Optimus |
|---|---|---|
| Bootstrapper officiel | Fonctionne en `-passive`, une fois .NET Framework 4.8 présent. | A échoué en `0x902` — mais WebView2 manquait et le préfixe était en Windows 7. |
| Échec du MSI | `0x80070643` faute de .NET Framework 4.8. | `LaunchConditions` avec `VersionNT = 601`. |
| Script Python (RunPythonScript) | **Ne démarre jamais.** Seul le moteur VBScript fonctionne. | **Fonctionne**, et tout le correctif de rafraîchissement en dépend. |
| Remède au rafraîchissement | Descendre le viewport à **OpenGL 2.1** (6,3 img/s contre 12,6 sur une scène de 1,3 Go). | Rester en **OpenGL 3.3** et forcer les redessins par script Python. |
| Grasshopper et greffons | Testé et fonctionnel : Pufferfish, Parakeet, LunchBox via Yak. | **Non testé.** |

## Pièges

| Symptôme | Cause | Remède |
|---|---|---|
| `apt install winehq-staging` échoue sur des dépendances introuvables. | Architecture 32 bits non activée. | `sudo dpkg --add-architecture i386 && sudo apt update` |
| Le fichier de dépôt WineHQ répond 404. | Nom de code de la distribution dérivée (« zena » sur Mint) au lieu de celui d'Ubuntu. | Lire `UBUNTU_CODENAME` dans `/etc/os-release`. |
| apt refuse le dépôt pour signature invalide. | Clé passée par `gpg --dearmor` ou placée sous un autre nom. | Déposer le `winehq.key` brut sous le nom exact du champ `Signed-By`. |
| `wine --version` affiche 9.0. | Le Wine de la distribution a pris la main dans le PATH. | `readlink -f "$(command -v wine)"` doit donner `/opt/wine-staging/bin/wine`. |
| **rhino.msi ne fait rien, sans erreur visible.** | Le préfixe est resté en Windows 7 : `load_dotnet48()` finit par `w_set_winver win7` sans restauration. | `wine winecfg /v win10` avant tout MSI. Signature dans le journal : `VersionNT = 601`. |
| Le journal MSI affiche `VersionNT = 603` et on croit à un échec. | En mode win10 Wine annonce 603, comme le vrai Windows 10. | 603 est la valeur **attendue**. Ne cherchez pas 1000. |
| L'installeur s'arrête sur un code du type `0x902`. | Le bootstrapper a échoué sur WebView2, préfixe encore en Windows 7. | Faire les étapes 9 et 10 *avant* de le lancer. |
| Le Desktop Runtime « s'installe » en quelques secondes, sans effet. | `find` a renvoyé une copie du moteur d'installation (622 Ko) au lieu du redistribuable (58 Mo). | Ajouter `-path '*/redist/*'` et contrôler la taille. |
| On cherche des dossiers à accolades pour les runtimes .NET, en vain. | Ils sont nommés par une empreinte SHA-1, sans accolades ni version. | Chercher par nom de fichier, jamais par motif de dossier. |
| Le journal winetricks contient des verbes non demandés. | `dotnet48` appelle `remove_mono` puis `dotnet40`, qui bascule en Windows XP. | Normal. Mais si vous l'interrompez, revérifiez la version Windows. |
| Un double-clic sur un `.3dm` ouvre un document vide. | Association manquante, et `%f` transmet un chemin Unix que Rhino ignore. | `MimeType=` + `xdg-mime default` + conversion `winepath -w`. |
| `pkill -9 -f "Rhino.exe"` tue le terminal. | La ligne de commande du shell contient elle-même le motif. | Écrire `pkill -9 -f 'Rhin[o]\.exe'`. |
| Une modification des réglages Rhino disparaît au redémarrage. | Rhino réécrit son XML en quittant, écrasant toute édition faite pendant qu'il tourne. | Éditer le XML Rhino **fermé**, ou passer par l'interface. |
| Le script Python de démarrage ne fonctionne plus. | Le moteur est IronPython 2.7 : f-strings et annotations le cassent. | Garder le script compatible Python 2. |
| `Version=win7` apparaît dans le registre après l'étape 9. | C'est une surcharge *par application* pour `msedgewebview2.exe`, posée par winetricks. | Ne pas la supprimer. La version globale se lit avec `wine winecfg /v`. |
| winetricks se fige indéfiniment après l'installation de WebView2. | `MicrosoftEdgeUpdate.exe` ne se termine jamais et bloque `wineserver -w`. | Le tuer avant ou pendant l'exécution de winetricks. |
| Les fils de Grasshopper sont droits au lieu d'être courbes. | GDI+ intégré de Wine. | `winetricks -q gdiplus` — confirmé sur la machine Ubuntu. |
| `winetricks` se fige 30 minutes en silence. | `MicrosoftEdgeUpdate.exe`, installé avec WebView2, ne se termine jamais, et `wineserver -w` attend la mort de tous les processus. | `pkill -f MicrosoftEdgeUpdate` débloque instantanément. |
| Un script d'automatisation reste bloqué à l'ouverture d'un fichier. | Le dialogue modal « Missing Fonts » s'ouvre si le document référence des polices absentes. | Cocher « Don't show again », et installer les polices manquantes. |
| `wine Rhino.exe /runscript="..."` ne fait rien. | Wine reconstruit la ligne de commande en enveloppant l'argument entier de guillemets, forme que Rhino ne reconnaît pas. | Passer par un `.bat` lancé avec `wine cmd /c`. |
| `-_RunScript C:\fichier.rvb` renvoie une erreur de syntaxe. | `RunScript` compile son argument comme du code ; c'est le deux-points du chemin qui casse. | Utiliser `-_LoadScript` pour exécuter un fichier. |
| `wine winecfg /v` n'affiche rien et on croit l'étape ratée. | Cette commande n'affiche pas la version courante sur Wine 11.16 — vérifié à l'exécution sur deux préfixes. | Lire le registre : `CurrentBuild` doit valoir 19045. |
| Le Package Manager fait planter Rhino instantanément. | Plantage silencieux dans les processus WebView2 embarqués. | Utiliser la ligne de commande Yak, pleinement fonctionnelle. |

## Ce qui ne fonctionne pas

- Rendu Cycles : **processeur uniquement**. Ni CUDA ni OptiX ne sont détectés sous Wine ; la carte n'est jamais utilisée pour le rendu final.
- Anticrénelage de viewport **impossible** : le chemin EGL de Wine n'expose aucun format de pixel multi-échantillon. Les exports `_-ViewCaptureToFile`, eux, sont anticrénelés.
- Le correctif de rafraîchissement **n'en est pas un** : il force des redessins, avec un coût, sans traiter la cause.
- Le Package Manager fait planter Rhino. La ligne de commande Yak fonctionne parfaitement.
- Sortie sale : processus orphelins à chaque fermeture, qui s'accumulent.
- Installation hors ligne **impossible** : l'exécutable officiel est un téléchargeur.
- Préfixe à usage unique : `dotnet48` retire Wine-Mono, ce qui casse les autres applications .NET du même préfixe.
- **Le jeton de licence n'est pas protégé** : sous Wine le DPAPI est factice. Ne publiez jamais le préfixe.
- Ce n'est **pas un bac à sable** : Rhino accède en écriture à vos Documents, Bureau et Téléchargements réels.
- Environ 8 Go occupés à l'arrivée, installeur compris.

## Ce que nous ne savons pas

- Ce dossier repose sur **deux machines seulement**, toutes deux NVIDIA propriétaire. Rien n'a été testé sur AMD ni sur Intel seul avec Rhino.
- **Aucun test sur Wayland natif** : X11 sur l'une, XWayland sur l'autre.
- Aucun test sur une autre distribution. Fedora et Arch n'ont pas de dépôt WineHQ ; Debian a d'autres noms de code.
- Une seule version de Rhino, 8.34. Une autre version changera les identifiants du cache et peut-être le comportement.
- Licence : seule l'évaluation Cloud Zoo a été essayée. Ni licence autonome, ni Zoo local.
- **La cause du problème de rafraîchissement n'est pas établie.** Les remèdes proposés sont des palliatifs dont on constate l'effet.
- L'ordre publié a été **rejoué et validé** le 2026-09-01 sur un préfixe neuf de la machine Mint : WebView2 puis Windows 10 puis l'installeur officiel, qui aboutit seul sans recours à l'installation manuelle. Cette réserve, présente dans les versions précédentes de ce document, est levée.

