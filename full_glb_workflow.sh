#!/bin/bash

# Full photo->3d point cloud->mesh workflow script
#
# Farran Rebbeck 
# 2015-12-15
# 

# Assumes both OpenMVG and OpenMVS build instructions are followed
# https://raw.githubusercontent.com/openMVG/openMVG/master/BUILD
# https://github.com/cdcseacave/openMVS/wiki/Building

# --- Variables and Directories set up here ---

# MAIN VARIABLES - DEPENDANT ON SYSTEM
OPENMVG_BUILD_DIR=/home/farran/dev/openMVG_Build
OPENMVG_INSTALL_DIR=/home/farran/dev/openMVG_Build/openMVG_install/
OPENMVS_BUILD_DIR=/home/farran/dev/openMVS_Build
PYTHON_LOC=`which python`
DEFAULT_OUTPUT_DIR=out
MATCHES_DIR=$DEFAULT_OUTPUT_DIR/matches
RECONSTRUCT_DIR=$DEFAULT_OUTPUT_DIR/recglo
CAMERA_SENSOR_DEFS=$OPENMVG_INSTALL_DIR/share/openMVG/sensor_width_camera_database.txt

# --- PROCESSING OPTIONS ---
# OVERRIDE INTRINSICS (For images that wont process properly)
FOCAL='24'
INTRINSICS='"f;0;ppx;0;f;ppy;0;0;1"'
# FEATURES
# Feature selection, can be SIFT/AKAZE_FLOAT/AKAZE_MLDB
CFEATURE_TYPE=SIFT
# Image Describer setup, can be NORMAL/HIGH/ULTRA
CDESC_TYPE=NORMAL
# MATCHING
# Nearest matching method, can be AUTO/BRUTEFORCEL2/BRUTEFORCEHAMMING/ANNL2
MMETHOD=AUTO

# Create working directories
if [ ! -d $DEFAULT_OUTPUT_DIR ]
then
    mkdir $DEFAULT_OUTPUT_DIR
fi

if [ ! -d $MATCHES_DIR ]
then
    mkdir $MATCHES_DIR
fi

if [ ! -d $RECONSTRUCT_DIR ]
then
    mkdir $RECONSTRUCT_DIR
fi

# Intrinsics Analysis
echo "Begin intrinsics analysis - image listing..."
$OPENMVG_INSTALL_DIR/bin/openMVG_main_SfMInit_ImageListing -i ./ -o $MATCHES_DIR -d $CAMERA_SENSOR_DEFS

# Compute Features
echo "Computing features within images..."
$OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeFeatures -i $MATCHES_DIR/sfm_data.bin -o $MATCHES_DIR -m $CFEATURE_TYPE -p $CDESC_TYPE

# Compute Matches
echo "Computing matches between features in images..."
$OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeMatches -i $MATCHES_DIR/sfm_data.bin -o $MATCHES_DIR -g e -n $MMETHOD

# Reconstruction - seq
echo "Performing Global reconstruction..."
$OPENMVG_INSTALL_DIR/bin/openMVG_main_GlobalSfM -i $MATCHES_DIR/sfm_data.bin -m $MATCHES_DIR -o $RECONSTRUCT_DIR

if [ $? -gt 0 ]
then
  echo "Failed to start reconstruction, likely camera data doesn't exist, or for GLOBAL we need all focal lengths must be the same."
  exit 1
fi

# Colorize structure
echo "Colorizing..."
$OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeSfM_DataColor -i $RECONSTRUCT_DIR/sfm_data.bin -o $RECONSTRUCT_DIR/colorized.ply

# Structure from known poses
echo "Structure from known poses..."
$OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeStructureFromKnownPoses -i $RECONSTRUCT_DIR/sfm_data.bin -m $MATCHES_DIR -f $MATCHES_DIR/matches.f.bin -o $RECONSTRUCT_DIR/robust.json

echo "Colorizing..."
$OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeSfM_DataColor -i $RECONSTRUCT_DIR/robust.json -o $RECONSTRUCT_DIR/robust_colorized.ply


# Export from OpenMVG to OpenMVS
$OPENMVS_BUILD_DIR/bin/InterfaceOpenMVG -i ./$RECONSTRUCT_DIR/sfm_data.bin -o ./$DEFAULT_OUTPUT_DIR/scene.mvs

# Create Dense Point Cloud
$OPENMVS_BUILD_DIR/bin/DensifyPointCloud ./$DEFAULT_OUTPUT_DIR/scene.mvs

# Create Mesh from Point Cloud
$OPENMVS_BUILD_DIR/bin/ReconstructMesh ./$DEFAULT_OUTPUT_DIR/scene_dense.mvs

# Create textures for PointCloudMesh
$OPENMVS_BUILD_DIR/bin/TextureMesh ./$DEFAULT_OUTPUT_DIR/scene_dense_mesh.mvs

# Cleanup of logs and stuff
echo "Cleanup..."
if [ ! -d logs ]
then
  mkdir logs
fi

mv *log ./logs/
rm *dmap

echo "Done!..."
