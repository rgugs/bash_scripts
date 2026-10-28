#!/usr/bin/env bash
#
# Tangible Landscape Installation Script
# Ubuntu 24.04 with Xbox One Kinect (libfreenect2) in Distrobox

# Create and enter Distrobox first

# distrobox create --name tangible-landscapes --image ubuntu:24.04
# distrobox enter tangible-landscapes

# Change the number of cores or any other variables in the script and save before continuing

# Run this inside the Distrobox container
# bash <FULL PATH TO SCRIPT>

# This script installs:
# - GRASS (compiled from source)
# - PCL (Point Cloud Library)
# - libfreenect2 (for Xbox One Kinect)
# - r.in.kinect GRASS tool
# - Tangible Landscape GRASS plugin
#

# Add error message if install fails
set -eE
trap 'echo "ERROR: \"$BASH_COMMAND\" failed at line $LINENO (exit code $?)" >&2' ERR

# Refuse to run outside a distrobox container
if [ -z "${CONTAINER_ID:-}" ] && [ ! -f /run/.containerenv ]; then
    echo "ERROR: run this script inside the distrobox container, not on the host." >&2
    echo "       e.g. distrobox enter tangible-landscapes" >&2
    exit 1
fi

# Set defaults so configuration dialogs should use default answers and sets timezone to UTC
export DEBIAN_FRONTEND=noninteractive
export TZ=UTC

# Ignore user's global git config (e.g. url.instead of rules that force SSH)
export GIT_CONFIG_GLOBAL=/dev/null

# Configuration - adjust versions as needed
GRASS_RELEASE=8.5.0
PCL_RELEASE=1.15.1
LIBFREENECT2_RELEASE=0.2.1
NCORES=8 # Original 4, but use 2 if on computer with limited memory or 8 have 12-16GB RAM available

# r.in.kinect source
KINECT_REPO=https://github.com/rgugs/r.in.kinect
KINECT_BRANCH=xbox-one-updated
KINECT_LOCAL=""   # optional: path to a local checkout (e.g. with the patch applied); leave empty to clone

# Changing path for containerization in distrobox, must be inside distrobox before running the script
# CDIR=$(pwd)
CDIR=/opt/tangible-landscape
sudo mkdir -p "$CDIR"
sudo chown "$USER": "$CDIR"
cd "$CDIR"


echo "=============================================="
echo "Tangible Landscape Installer"
echo "Ubuntu 24.04 + Xbox One Kinect (libfreenect2)"
echo "=============================================="
echo "Using ${NCORES} cores for compilation"
echo ""

# Package dependencies
echo "Installing system dependencies..."
sudo apt-get update && sudo apt-get install -y software-properties-common && \
   sudo add-apt-repository -y ppa:ubuntugis/ubuntugis-unstable && \
   sudo apt-get update && sudo apt-get install -y \
   build-essential cmake curl pkg-config git wget \
   libusb-1.0-0-dev libturbojpeg0-dev libglfw3-dev \
   libboost-all-dev libeigen3-dev libflann-dev libopencv-dev \
   flex make bison gcc libgcc-s1 g++ ccache \
   python3-dateutil libgsl-dev \
   python3-numpy python3-pil python3-matplotlib python3-watchdog \
   python3-wxgtk4.0 python3-wxgtk-webview4.0 python3-pip \
   python-is-python3 \
   libncurses-dev \
   zlib1g-dev gettext \
   libtiff-dev libpnglite-dev \
   libcairo2 libcairo2-dev \
   sqlite3 libsqlite3-dev \
   libpq-dev \
   libreadline-dev libfreetype6-dev \
   libfftw3-double3 libfftw3-dev \
   libboost-thread-dev libboost-program-options-dev \
   subversion \
   libavutil-dev \
   libavcodec-dev \
   libavformat-dev libswscale-dev \
   libglu1-mesa-dev libxmu-dev \
   ghostscript \
   libproj-dev proj-data proj-bin \
   libgeos-dev \
   libgdal-dev python3-gdal gdal-bin \
   libzstd-dev \
   libpdal-dev \
   libsdl2-dev \
   liblapacke-dev


# wxPython
# Commented out because already installed by apt package
# pip install -U -f https://extras.wxpython.org/wxPython4/extras/linux/gtk3/ubuntu-24.04 wxPython

# ============================================
# libfreenect2 (Xbox One Kinect)
# ============================================
echo ""
echo "Installing libfreenect2 ${LIBFREENECT2_RELEASE}..."

if [ -f /usr/local/lib/libfreenect2.so ]; then
    echo "libfreenect2 already installed, skipping."
else

wget https://github.com/OpenKinect/libfreenect2/archive/refs/tags/v${LIBFREENECT2_RELEASE}.tar.gz
tar xvf v${LIBFREENECT2_RELEASE}.tar.gz
rm v${LIBFREENECT2_RELEASE}.tar.gz
cd libfreenect2-${LIBFREENECT2_RELEASE}
mkdir -p build && cd build
cmake -DENABLE_CUDA:BOOL=OFF ..
make -j${NCORES}
sudo make install
sudo mkdir -p /etc/udev/rules.d
sudo cp ../platform/linux/udev/90-kinect2.rules /etc/udev/rules.d/
cd ../..
fi

# ============================================
# PCL (Point Cloud Library)
# ============================================
echo ""
echo "Installing PCL ${PCL_RELEASE}..."

if [ -f /usr/local/lib/libpcl_segmentation.so ]; then
    echo "PCL already installed, skipping."
else

if [ ! -d "pcl-pcl-${PCL_RELEASE}" ]; then
    wget "https://github.com/PointCloudLibrary/pcl/archive/pcl-${PCL_RELEASE}.tar.gz"
    tar xvf "pcl-${PCL_RELEASE}.tar.gz"
    rm "pcl-${PCL_RELEASE}.tar.gz"
fi

cd "pcl-pcl-${PCL_RELEASE}"
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j${NCORES}
sudo make install
cd ../..
fi

# ============================================
# GRASS
# ============================================
echo ""
echo "Installing GRASS ${GRASS_RELEASE}..."

if [ -x /usr/local/bin/grass ]; then
    echo "GRASS already installed, skipping."
else

if [ ! -d "grass" ]; then
    git clone --branch ${GRASS_RELEASE} --depth 1 https://github.com/OSGeo/grass
fi

cd grass
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DWITH_READLINE=ON
cmake --build build -j${NCORES}
sudo cmake --install build
cd ..
fi

# Determine GRASS version directory
GRASS_VERSION_SHORT=$(echo ${GRASS_RELEASE} | cut -d. -f1,2 | tr -d '.')

sudo ldconfig

# ============================================
# r.in.kinect (GRASS tool for Xbox One Kinect)
# ============================================
echo ""
echo "Installing r.in.kinect ..."

if [ -n "$KINECT_LOCAL" ]; then
    KINECT_DIR="$KINECT_LOCAL"
else
    if [ ! -d "r.in.kinect" ]; then
        git clone "$KINECT_REPO" --branch "$KINECT_BRANCH"
    else
        git -C r.in.kinect fetch
        git -C r.in.kinect checkout "$KINECT_BRANCH"
        git -C r.in.kinect pull
    fi
    KINECT_DIR="$CDIR/r.in.kinect"
fi

sudo grass --tmp-project XY --exec \
    g.extension -s extension=r.in.kinect url="$KINECT_DIR"


# ============================================
# Tangible Landscape GRASS Plugin
# ============================================
echo ""
echo "Installing Tangible Landscape plugin (master)..."

if [ ! -d "grass-tangible-landscape" ]; then
    git clone https://github.com/tangible-landscape/grass-tangible-landscape
else
    cd grass-tangible-landscape
    git fetch
    git checkout master
    git pull
    cd ..
fi

cd grass-tangible-landscape
sudo grass --tmp-project XY --exec \
    g.extension -s extension=g.gui.tangible url="$(pwd)"
cd ..

# ============================================
# Desktop Entry for GRASS and Kinect
# ============================================
echo ""
echo "Creating desktop entry..."

cat << EOF > /tmp/grass.desktop
[Desktop Entry]
Version=1.0
Name=GRASS
Comment=Start GRASS
Exec=/usr/local/bin/grass
Icon=/usr/local/lib/grass${GRASS_VERSION_SHORT}/share/icons/hicolor/scalable/apps/grass.svg
Terminal=true
Type=Application
Categories=Science;Geography;GIS;
EOF
sudo mv /tmp/grass.desktop /usr/share/applications/grass.desktop


cat << EOF > /tmp/kinect.desktop
[Desktop Entry]
Version=1.0
Name=Kinect Protonect
Comment=Start Kinect
Exec=${CDIR}/libfreenect2-${LIBFREENECT2_RELEASE}/build/bin/Protonect
Icon=
Terminal=true
Type=Application
Categories=Science;Geography;GIS;
EOF
sudo mv /tmp/kinect.desktop /usr/share/applications/kinect.desktop


# ============================================
# Final Configuration
# ============================================
echo ""
echo "Running ldconfig..."
sudo ldconfig

# Exports the desktop entries outside the distrobox container
distrobox-export --app /usr/share/applications/grass.desktop
distrobox-export --app /usr/share/applications/kinect.desktop

echo ""
echo "=============================================="
echo "Installation Complete!"
echo "=============================================="
echo ""

cat << EOF

HOST STEP REQUIRED (run these in a terminal on the HOST, not the container):

  distrobox enter ${CONTAINER_ID:-<container-name>} -- cat ${CDIR}/libfreenect2-${LIBFREENECT2_RELEASE}/platform/linux/udev/90-kinect2.rules | sudo tee /etc/udev/rules.d/90-kinect2.rules > /dev/null
  sudo udevadm control --reload-rules && sudo udevadm trigger

Then unplug and replug the Kinect.

To start GRASS: use the GRASS launcher in the host menu, or run 'grass' in the container.
EOF
