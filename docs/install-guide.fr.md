# Installer Rhino 8 sur Linux

Onze étapes à suivre dans l'ordre. Vous n'avez rien à comprendre au code : chaque bloc se copie, se colle, et le guide vous dit ce que vous devez voir ensuite.

**Environ 1 h 30 · 12 Go d'espace disque · Ubuntu 24.04+ ou Mint 22+ · un compte McNeel**

> **À savoir avant de commencer.** Rhino est un logiciel payant : il vous faut un compte sur rhino3d.com et une licence, ou l'évaluation gratuite de 90 jours. Cette méthode n'est pas officielle et McNeel ne la soutient pas — elle fonctionne, mais certaines fonctions resteront indisponibles, notamment le rendu final sur carte graphique.

---

## 1. Ouvrir le Terminal

*1 minute*

Presque tout se fait en collant des commandes dans le Terminal. Ouvrez-le avec le raccourci **Ctrl + Alt + T**, ou cherchez « Terminal » dans le menu des applications. Pour chaque étape, copiez le bloc entier, collez-le et appuyez sur Entrée.

> **Ce que vous devez voir** — Une fenêtre noire avec une ligne de texte qui attend. C'est normal.

## 2. Préparer le système et installer Wine

*10 à 15 minutes*

Wine est le programme qui permet de faire tourner un logiciel Windows sous Linux. La version fournie par votre distribution est trop ancienne pour Rhino : on installe donc la version officielle. Le mot de passe vous sera demandé — c'est normal, et il ne s'affiche pas pendant que vous le tapez.

```bash
sudo dpkg --add-architecture i386
. /etc/os-release && CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
sudo wget -NP /etc/apt/sources.list.d/ "https://dl.winehq.org/wine-builds/ubuntu/dists/$CODENAME/winehq-$CODENAME.sources"
sudo apt update
sudo apt install -y --install-recommends winehq-staging
wine --version
```

> **Ce que vous devez voir** — La dernière ligne doit afficher un numéro commençant par **11**, suivi de « Staging ». Si elle affiche 9.0, quelque chose n'a pas fonctionné : ne continuez pas.

## 3. Installer l'assistant winetricks

*1 minute*

winetricks installe automatiquement les composants Windows dont Rhino a besoin. On prend la version la plus récente, celle des dépôts ayant deux ans de retard.

```bash
mkdir -p "$HOME/.local/bin"
wget -O "$HOME/.local/bin/winetricks" https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x "$HOME/.local/bin/winetricks"
hash -r && winetricks --version
```

> **Ce que vous devez voir** — Une date récente s'affiche, du type `20260125`. Si c'est une date de 2024, c'est l'ancienne version qui répond.

## 4. Créer l'espace Windows de Rhino

*2 minutes*

Wine crée un faux disque Windows dans un dossier : un « préfixe ». Rhino y vivra, isolé du reste. Gardez ce dossier réservé à Rhino, n'y installez rien d'autre.

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
export WINEARCH=win64
WINEDLLOVERRIDES="mscoree=d;mshtml=d" wineboot --init
```

> **Ce que vous devez voir** — Des lignes défilent, puis la main revient. Un dossier a été créé. **Gardez ce Terminal ouvert** jusqu'à la fin du guide.

## 5. Installer les composants Windows

*30 à 45 minutes*

C'est la plus longue étape, et elle se déroule sans vous. Des fenêtres d'installation Microsoft vont apparaître et disparaître toutes seules : **n'y touchez pas**. Allez faire autre chose.

```bash
winetricks -q corefonts d3dcompiler_47 vcrun2022 dotnet48
```

> **Ce que vous devez voir** — La main revient au bout d'une bonne demi-heure. Si le Terminal semble figé plus de dix minutes sans rien afficher, voyez la section « Si ça coince » en bas de page.

## 6. Remettre Windows 10 — ne sautez pas cette étape

*10 secondes*

L'étape précédente a discrètement basculé l'espace de Rhino en **Windows 7**. Si vous ne corrigez pas, l'installation de Rhino échouera plus loin **sans afficher la moindre erreur** — c'est le piège qui fait perdre le plus de temps.

```bash
wine winecfg /v win10
wine reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild
```

> **Ce que vous devez voir** — La dernière ligne doit afficher **19045**. C'est le numéro de Windows 10 ; 7601 signifierait Windows 7. Si vous voyez 7601, relancez la première commande.

## 7. Installer le composant navigateur

*5 à 10 minutes*

Rhino affiche sa fenêtre de licence à l'aide d'un composant navigateur de Microsoft. Sans lui, cette fenêtre reste **blanche** et vous ne pouvez pas activer votre licence. Il faut l'installer **avant** Rhino, pas après.

```bash
winetricks -q webview2
wine reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild
```

> **Ce que vous devez voir** — La main revient, et la dernière ligne affiche toujours **19045**.

## 8. Télécharger Rhino

*10 minutes*

Rendez-vous sur **rhino3d.com**, connectez-vous avec votre compte McNeel et téléchargez la version Windows de Rhino 8. Le fichier fait environ 600 Mo. Une évaluation gratuite de 90 jours est proposée si vous n'avez pas encore de licence.



Restez connecté à internet pour la suite : ce fichier est en réalité un téléchargeur, il ira chercher plusieurs centaines de mégaoctets supplémentaires pendant l'installation.

> **Ce que vous devez voir** — Un fichier nommé `rhino_en-us_8….exe` dans votre dossier Téléchargements.

## 9. Installer Rhino

*15 minutes*

On lance l'installateur officiel. Il travaille tout seul ; laissez-le finir sans cliquer ailleurs.

```bash
wine ~/Téléchargements/rhino_en-us_8*.exe -passive -norestart
# si vos dossiers sont en anglais, remplacez Téléchargements par Downloads
ls "$WINEPREFIX/drive_c/Program Files/Rhino 8/System/Rhino.exe"
```

> **Ce que vous devez voir** — La dernière commande doit afficher un chemin se terminant par `Rhino.exe`. Si elle dit « Aucun fichier », l'installation a échoué : voyez « Si ça coince ».

## 10. Créer le raccourci de lancement

*2 minutes*

Ces commandes créent un petit programme de démarrage et l'ajoutent à votre menu, pour ne plus avoir à passer par le Terminal.

```bash
cat > "$HOME/.local/bin/rhino8.sh" <<'FIN'
#!/usr/bin/env bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
export WINEDEBUG=-all
args=()
for f in "$@"; do
  if [ -e "$f" ]; then args+=("$(winepath -w "$f")"); else args+=("$f"); fi
done
exec wine "C:\\Program Files\\Rhino 8\\System\\Rhino.exe" ${args[@]+"${args[@]}"}
FIN
chmod +x "$HOME/.local/bin/rhino8.sh"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/rhino8.desktop" <<FIN
[Desktop Entry]
Type=Application
Name=Rhinoceros 8
Exec=$HOME/.local/bin/rhino8.sh %f
Terminal=false
Categories=Graphics;3DGraphics;
FIN
update-desktop-database "$HOME/.local/share/applications"
```

> **Ce que vous devez voir** — Rien ne s'affiche, c'est bon signe. **Rhinoceros 8** apparaît maintenant dans votre menu d'applications.

## 11. Premier démarrage et licence

*5 minutes*

Lancez Rhino depuis votre menu. Le premier démarrage est lent, comptez une minute. Une fenêtre vous demandera votre adresse e-mail pour activer la licence, et votre navigateur s'ouvrira pour la validation.



Des messages d'avertissement défilent parfois dans le Terminal, notamment sur `libEGL`. **Ils sont normaux** et n'indiquent aucun problème.

> **Ce que vous devez voir** — La fenêtre principale de Rhino s'ouvre, avec ses quatre vues. Si la fenêtre de licence semble à moitié dessinée, redimensionnez-la : elle se complète.

---

## Si ça coince

**Le Terminal semble figé pendant l'étape 5 ou 7.**

Un composant Microsoft reste bloqué en arrière-plan. Ouvrez un *second* Terminal et collez : `pkill -f MicrosoftEdgeUpdate`. Le premier repart aussitôt.

**`wine --version` affiche 9.0 au lieu de 11.**

L'ancienne version de Wine de votre distribution répond encore. Vérifiez que l'étape 2 s'est terminée sans erreur, en particulier la ligne `apt install`.

**L'installation de Rhino se termine mais Rhino n'est nulle part.**

Dans presque tous les cas, c'est l'étape 6 qui a été sautée ou qui n'a pas pris. Recommencez-la, vérifiez que la réponse est bien `win10`, puis relancez l'étape 9.

**La fenêtre de licence reste blanche.**

Le composant navigateur de l'étape 7 manque ou a échoué. Refermez Rhino et relancez cette étape.

**Une vue reste figée et la sélection n'apparaît pas.**

C'est un défaut connu de Wine, sans solution simple à ce jour. Contournement immédiat : faites tourner légèrement la vue à la souris, l'affichage se met à jour. Une correction existe mais demande des compétences avancées — elle figure dans le dossier technique.

---

Testé sur Linux Mint 22.3 et Ubuntu 26.04, avec Rhino 8.34 et Wine 11 staging, sur deux machines équipées de cartes NVIDIA. Les configurations AMD et Intel n'ont pas été essayées.
