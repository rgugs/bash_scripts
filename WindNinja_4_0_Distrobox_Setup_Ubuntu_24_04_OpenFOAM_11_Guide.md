# WindNinja 4.0 Distrobox Setup (Ubuntu 24.04 + OpenFOAM 11)

Oct 6, 2026 · @Rachel

## Overview

This guide rebuilds a working WindNinja 4.0.0 setup (GUI, CLI and momentum solver) inside an Ubuntu 24.04 distrobox, using OpenFOAM 11. It was tested on 2026-10-05.

| Component | Version / value |
| --- | --- |
| Container | `windninja-2404`, image `ubuntu:24.04` |
| WindNinja | 4.0.0, source in `~/Desktop/Code/windninja` |
| OpenFOAM | 11 (dl.openfoam.org package) |
| Build folder | `~/Desktop/Code/windninja-build-2404` |
| Libraries | Qt 6, GDAL, Boost, shapelib from Ubuntu repos |

Two conventions apply throughout. Each step says whether it runs on the **host** or **inside the container**. And because distrobox shares your home directory with the host, no step edits `~/.bashrc`; the environment lives in wrapper scripts instead.

Paths use the username `rgugler`. Replace it with yours.

## Container and dependencies (steps 1-4)

Steps 1 to 4 create the container and install everything WindNinja needs except OpenFOAM.

### Step 1: Create and enter the container (host)

```
distrobox create --name windninja-2404 --image ubuntu:24.04
distrobox enter windninja-2404
```

The first entry runs distrobox's initial setup and takes a while.

### Step 2: Install base build tools (container)

```
sudo apt update
sudo apt install -y build-essential cmake git wget ca-certificates gnupg software-properties-common
```

### Step 3: Install WindNinja dependencies (container)

These are the `apt` lines from the repo's `scripts/build_deps_ubuntu_2404.sh`, run directly so the script's `~/.bashrc` edit never touches your shared home.

```
sudo apt install -y pkg-config libboost-program-options-dev libboost-date-time-dev libboost-test-dev libshp-dev qt6-base-dev qt6-webengine-dev libgdal-dev libhwloc-dev
```

### Step 4: Get the source (container)

Skip this if you already have a checkout. Because home is shared, the container sees a checkout made on the host.

```
mkdir -p ~/Desktop/Code && git clone https://github.com/firelab/windninja.git ~/Desktop/Code/windninja
```

## OpenFOAM 11 (step 5)

OpenFOAM 11 comes from the openfoam.org repository and installs into `/opt/openfoam11`. Skip this step if you only need the default mass-conserving solver.

### Step 5: Install OpenFOAM 11 (container)

```
sudo sh -c "wget -O - https://dl.openfoam.org/gpg.key > /etc/apt/trusted.gpg.d/openfoam.asc"
sudo add-apt-repository -y http://dl.openfoam.org/ubuntu
sudo apt update
sudo apt install -y openfoam11
```

The install pulls in ParaView and about 220 packages (roughly 430 MB to download, 2 GB on disk). Two things in its output are safe to ignore:

- Python `SyntaxWarning: invalid escape sequence` lines from ParaView's bundled files.
- A message telling you to add `. /opt/openfoam11/etc/bashrc` to `~/.bashrc`. Don't: your home is shared with the host. The wrapper scripts in step 8 load it instead.

Check that it works in the current terminal only:

```
source /opt/openfoam11/etc/bashrc && blockMesh -help | head -5
echo $FOAM_RUN
```

`$FOAM_RUN` should print `/home/<user>/OpenFOAM/<user>-11/run`. Step 7 needs it.

## Building WindNinja (steps 6-7)

The momentum solver needs two pieces: WindNinja configured with `NINJAFOAM=ON`, and WindNinja's own OpenFOAM library built with `wmake`. Miss either and the solver option appears in the GUI but will not run.

### Step 6: Configure and build WindNinja (container)

Build in a folder outside the source tree, and use a separate build folder per container or OS version, because a build folder caches compilers and library paths.

```
mkdir -p ~/Desktop/Code/windninja-build-2404 && cd ~/Desktop/Code/windninja-build-2404
cmake -DNINJA_CLI=ON -DNINJA_GUI=ON -DNINJAFOAM=ON ../windninja
make -j$(nproc)
```

`-D` is CMake's command-line syntax for setting an option; the three names match the ones in the WindNinja wiki. Note `NINJAFOAM` has no underscore. When it finishes, `src/cli/WindNinja_cli` and `src/gui/WindNinja` exist in the build folder.

### Step 7: Build the custom OpenFOAM library (container)

The source ships OpenFOAM code only for versions 11, 9 and 2.2.0, which is why this guide uses 11. Run this in a terminal where OpenFOAM's environment is loaded:

```
source /opt/openfoam11/etc/bashrc
mkdir -p $FOAM_RUN/../applications
cp -r ~/Desktop/Code/windninja/src/ninjafoam/11/* $FOAM_RUN/../applications
cd $FOAM_RUN/../applications && wmake libso
cd utility/applyInit && wmake
```

Confirm both outputs were built:

```
find ~/OpenFOAM -name "applyInit" -type f -o -name "libWindNinja.so"
```

Expect one `applyInit` and one `libWindNinja.so`. They land under `platforms/linux64GccDPInt32Opt/`, not the `linux64GccDPOpt/` path the wiki names; the wiki's folder name is out of date for OpenFOAM 11, and the build works regardless.

## Wrapper scripts (step 8)

A desktop icon does not read `~/.bashrc`, so each wrapper sets the whole environment itself: OpenFOAM, the API keys file and `WINDNINJA_DATA`. The keys line is guarded, so the scripts work before step 9 creates that file.

### Step 8: Create the GUI and CLI wrappers (host or container)

Home is shared, so either side works. The CLI wrapper differs in two places: it runs `WindNinja_cli`, and it ends with `"$@"` to pass your arguments through.

```
mkdir -p ~/bin

cat > ~/bin/windninja-2404.sh << 'EOF'
#!/bin/bash
source /opt/openfoam11/etc/bashrc
[ -f ~/.config/windninja/keys.env ] && source ~/.config/windninja/keys.env
export WINDNINJA_DATA=/home/rgugler/Desktop/Code/windninja/data
exec /home/rgugler/Desktop/Code/windninja-build-2404/src/gui/WindNinja
EOF

cat > ~/bin/windninja-cli-2404.sh << 'EOF'
#!/bin/bash
source /opt/openfoam11/etc/bashrc
[ -f ~/.config/windninja/keys.env ] && source ~/.config/windninja/keys.env
export WINDNINJA_DATA=/home/rgugler/Desktop/Code/windninja/data
exec /home/rgugler/Desktop/Code/windninja-build-2404/src/cli/WindNinja_cli "$@"
EOF

chmod 700 ~/bin/windninja-2404.sh ~/bin/windninja-cli-2404.sh
```

### Check both wrappers

From a clean environment (container), which approximates an icon launch. The GUI should open:

```
env -i HOME=$HOME DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR ~/bin/windninja-2404.sh
```

From the host, the CLI should print `WindNinja version: 4.0.0`:

```
distrobox enter windninja-2404 -- ~/bin/windninja-cli-2404.sh --version
```

### Check the momentum solver

In the GUI, run this small test case:

1. Surface Input: load `~/Desktop/Code/windninja/data/big_butte_small.tif` and set the mesh to Coarse.
2. Solver Methodology: select "Conservation of Mass and Momentum" and tick **Use Conservation of Mass and Momentum**. Selecting the entry alone only shows its description page.
3. Domain Average Wind: 10 mph from 270 degrees.
4. Outputs: enable at least one output and set a writable folder. A run will not start without one.
5. Run. The test finished successfully on the 24.04 build.

## API keys (step 9)

The keys are optional: the GUI, local elevation files and the momentum solver all work without them. They are only needed for data downloads, and WindNinja reads them from environment variables only; the GUI has no field for them. The wrappers load them from one private file, so no secret sits in a script.

### Step 9a: Create the keys file (host or container)

```
mkdir -p ~/.config/windninja && touch ~/.config/windninja/keys.env && chmod 600 ~/.config/windninja/keys.env
```

### Step 9b: SRTM elevation downloads (OpenTopography)

Create an account at opentopography.org, then request a key at portal.opentopography.org/myopentopo. Open the keys file in an editor and add one line, with your key in place of `YOUR_KEY` and the quotes kept:

```
export CUSTOM_SRTM_API_KEY='YOUR_KEY'
```

Per the WindNinja wiki, `CUSTOM_SRTM_API_KEY` overrides `NINJA_GUI_SRTM_API_KEY` and `NINJA_CLI_SRTM_API_KEY`, so this one line covers both the GUI and CLI.

### Step 9c: HRRR pastcasts (Google Cloud)

This needs `jq` installed. The pastcast data is served from Google Cloud and needs a service account:

1. Open console.cloud.google.com/iam-admin/serviceaccounts and sign in. Create a project if asked, then create a service account; the optional role steps can be skipped.
2. Open the account's **Keys** tab, choose **Add key**, **Create new key**, **JSON**, then **Create**. A JSON file downloads.
3. Extract the private key into the config folder (replace the path with your downloaded file):

```
jq -r '.private_key' /path/to/downloaded.json > ~/.config/windninja/gcp_private_key.pem && chmod 600 ~/.config/windninja/gcp_private_key.pem
```

4. Append both variables to the keys file, reading the account email straight from the JSON:

```
printf "export GS_OAUTH2_PRIVATE_KEY_FILE='%s'\nexport GS_OAUTH2_CLIENT_EMAIL='%s'\n" "$HOME/.config/windninja/gcp_private_key.pem" "$(jq -r '.client_email' /path/to/downloaded.json)" >> ~/.config/windninja/keys.env
```

5. Delete the downloaded JSON. It holds the full private key, only the extracted `.pem` is needed, and a new key can be created from the same page later.

### Check the keys

Relaunch the GUI from the wrapper so it picks up the new variables. For SRTM, download an elevation file from Surface Input. For HRRR, choose weather model initialization with **PASTCAST-GCP-HRRR-CONUS-3-KM**, a DEM inside the continental US and a past date. Both worked in testing.

The wiki's section on Synoptic weather station keys was empty when this was written, so that key is not covered here.

## Launcher and host command (steps 10-11)

Steps 10 and 11 make the GUI a menu entry and the CLI a plain command on the host.

### Step 10: Create the desktop launcher (host or container)

The launcher is a hand-written `.desktop` file rather than a `distrobox-export --app` export, because that export is meant for apps installed in the container with their own `.desktop` file, and a binary built from source has none. The icon is the `wn-icon.png` file from the WindNinja repo. `StartupWMClass=WindNinja` makes the taskbar match the running window to this launcher, which fixed a generic Wayland icon in the taskbar during testing.

```
mkdir -p ~/.local/share/applications && cat > ~/.local/share/applications/windninja-2404.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=WindNinja (24.04)
Icon=/home/rgugler/Desktop/Code/windninja/images/icons/wn-icon.png
StartupWMClass=WindNinja
Exec=distrobox enter windninja-2404 -- /home/rgugler/bin/windninja-2404.sh
Terminal=false
Categories=Science;
EOF
```

The menu may not show the entry until its cache is rebuilt. On KDE Plasma (the desktop used here) run this on the host; other desktops have their own refresh method that was not tested:

```
kbuildsycoca6
```

Then find "WindNinja (24.04)" in the application menu and launch it.

### Step 11: Expose the CLI as a host command (container)

```
distrobox-export --bin ~/bin/windninja-cli-2404.sh --export-path ~/.local/bin
```

This only works if `~/.local/bin` is on the host's `PATH`, which it was here. Check from a host terminal:

```
windninja-cli-2404.sh --version
```

It should print `WindNinja version: 4.0.0`.

## Troubleshooting notes

The GUI crashed once on 24.04 and several messages look alarming but are harmless; the table covers what was seen and what to do.

| Symptom | What it is | What to do |
| --- | --- | --- |
| GUI crashes (SEGV) while typing wind input | The core dump showed one Qt 6.4.2 Wayland and Widgets call chain repeating about 60 times. It happened once and did not reproduce. | Add `export QT_QPA_PLATFORM=xcb` above the `exec` line in `~/bin/windninja-2404.sh` to run through XWayland. This is untested as a fix. Possible costs: softer scaling on high-DPI screens and a changed taskbar icon match. Inspect crashes with `coredumpctl info`. |
| `Failed to connect to the bus ... system_bus_socket` in the terminal | A QtWebEngine (Chromium) warning; the container has no system D-Bus. | Ignore it. The map still loads. |
| `SyntaxWarning: invalid escape sequence` during the OpenFOAM install | Old regex strings in ParaView's bundled Python files. | Ignore it. |
| Momentum solver can be selected but will not run | Selecting the entry only shows its page. Running needs `NINJAFOAM=ON` and the custom library from step 7. | Re-check steps 6 and 7, and that you ticked the Use box. |
| Run will not start | No output is enabled. | Enable at least one output and set a writable folder. |
| Taskbar shows a generic Wayland icon | The running window is not matched to the launcher. | Keep `StartupWMClass=WindNinja` in the `.desktop` file, then run `kbuildsycoca6`. |

### 
