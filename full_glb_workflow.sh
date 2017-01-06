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
DTSTAMP=`date +%y%m%d-%H%M%S`
DEFAULT_OUTPUT_DIR=out-$DTSTAMP
MATCHES_DIR=$DEFAULT_OUTPUT_DIR/matches
RECONSTRUCT_DIR=$DEFAULT_OUTPUT_DIR/recseq
CAMERA_SENSOR_DEFS=$OPENMVG_INSTALL_DIR/share/openMVG/sensor_width_camera_database.txt

# --- PROCESSING OPTIONS ---
# OVERRIDE INTRINSICS (For images that wont process properly)
FOCAL='24'
INTRINSICS='"f;0;ppx;0;f;ppy;0;0;1"'

# THREADS
THREADS=7

# FEATURES
# Feature selection, can be SIFT/SIFT_ANATOMY/AKAZE_FLOAT/AKAZE_MLDB
echo -e "Feature selection:\n 1)SIFT \n 2)SIFT_ANATOMY \n 3)AKAZE_FLOAT \n 4)AKAZE_MLDB"
read -p "> " CFEATURE_TYPE
case $CFEATURE_TYPE in
1)
CFEATURE_TYPE=SIFT
;;
2)
CFEATURE_TYPE=SIFT_ANATOMY
;;
3)
CFEATURE_TYPE=AKAZE_FLOAT
;;
4)
CFEATURE_TYPE=AKAZE_MLDB
;;
*)
CFEATURE_TYPE=AKAZE_FLOAT
;;
esac


# Image Describer setup, can be NORMAL/HIGH/ULTRA
echo -e "Which describer standard to use:\n 1)NORMAL \n 2)HIGH \n 3)ULTRA (Takes a long time)"
read -p "> " CDESC_TYPE
case $CDESC_TYPE in
1)
CDESC_TYPE=NORMAL
;;
2)
CDESC_TYPE=HIGH
;;
3)
CDESC_TYPE=ULTRA
;;
*)
CDESC_TYPE=NORMAL
;;
esac


# MATCHING
# Nearest matching method, can be AUTO/BRUTEFORCEL2/ANNL2/CASCADEHASHINGL2/FASTCASCADEHASHINGL2/bin BRUTEFORCEHAMMING
echo -e "Matching method to use:\n 1)AUTO \n 2)BRUTEFORCEL2 \n 3)ANNL2 \n 4)CASCADEHASHINGL2 \n 5)FASTCASCADEHASHINGL2 \n 6)BRUTEFORCEHAMMING"
read -p "> " MMETHOD
case $MMETHOD in
1)
MMETHOD=AUTO
;;
2)
MMETHOD=BRUTEFORCEL2
;;
3)
MMETHOD=ANNL2
;;
4)
MMETHOD=CASCADEHASHINGL2
;;
5)
MMETHOD=FASTCASCADEHASHINGL2
;;
6)
MMETHOD=BRUTEFORCEHAMMING
;;
*)
MMETHOD=AUTO
;;
esac

# Ratio
echo -e "Enter a matching ratio, default 0.6, 0.8 recommended:"
read -p "> " MRATIO
if [ -z $MRATIO ]
then
MRATIO=0.6
fi


# Robust filtering (Wont affect MVS)
echo -e "Enter a filtering setting for robust filtering, default 4, for big messy sets, use <1:"
read -p "> " ROBUSTFILTER
if [ -z $ROBUSTFILTER ]
then
ROBUSTFILTER=0.5
fi


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
echo "RUN: $OPENMVG_INSTALL_DIR/bin/openMVG_main_SfMInit_ImageListing -i ./ -o $MATCHES_DIR -d $CAMERA_SENSOR_DEFS"
$OPENMVG_INSTALL_DIR/bin/openMVG_main_SfMInit_ImageListing -i ./ -o $MATCHES_DIR -d $CAMERA_SENSOR_DEFS

# Compute Features
echo "Computing features within images..."
echo "RUN: $OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeFeatures -i $MATCHES_DIR/sfm_data.json -o $MATCHES_DIR -m $CFEATURE_TYPE -p $CDESC_TYPE -n $THREADS"
$OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeFeatures -i $MATCHES_DIR/sfm_data.json -o $MATCHES_DIR -m $CFEATURE_TYPE -p $CDESC_TYPE -n $THREADS

# Compute Matches
echo "Computing matches between features in images..."
echo "RUN: $OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeMatches -i $MATCHES_DIR/sfm_data.json -g e -o $MATCHES_DIR -n $MMETHOD -r $MRATIO"
$OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeMatches -i $MATCHES_DIR/sfm_data.json -g e -o $MATCHES_DIR -n $MMETHOD -r $MRATIO

# Reconstruction - seq
echo "Performing Global reconstruction..."
echo "RUN: $OPENMVG_INSTALL_DIR/bin/openMVG_main_IncrementalSfM -i $MATCHES_DIR/sfm_data.json -m $MATCHES_DIR -o $RECONSTRUCT_DIR"
$OPENMVG_INSTALL_DIR/bin/openMVG_main_GlobalSfM -i $MATCHES_DIR/sfm_data.json -m $MATCHES_DIR -o $RECONSTRUCT_DIR

if [ $? -gt 0 ]
then
  echo "Failed to start reconstruction, likely camera data doesn't exist."
  exit 1
fi

# Colorize structure
echo "Colorizing..."
echo "RUN: $OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeSfM_DataColor -i $RECONSTRUCT_DIR/sfm_data.bin -o $RECONSTRUCT_DIR/colorized.ply"
$OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeSfM_DataColor -i $RECONSTRUCT_DIR/sfm_data.bin -o $RECONSTRUCT_DIR/colorized.ply

# Structure from known poses
echo "Structure from known poses..."
echo "RUN: $OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeStructureFromKnownPoses -i $RECONSTRUCT_DIR/sfm_data.bin -m $MATCHES_DIR -f $MATCHES_DIR/matches.f.bin -o $RECONSTRUCT_DIR/robust.json -r $ROBUSTFILTER"
$OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeStructureFromKnownPoses -i $RECONSTRUCT_DIR/sfm_data.bin -m $MATCHES_DIR -f $MATCHES_DIR/matches.f.bin -o $RECONSTRUCT_DIR/robust.json -r $ROBUSTFILTER

echo "Colorizing..."
echo "RUN: $OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeSfM_DataColor -i $RECONSTRUCT_DIR/robust.json -o $RECONSTRUCT_DIR/robust_colorized.ply"
$OPENMVG_INSTALL_DIR/bin/openMVG_main_ComputeSfM_DataColor -i $RECONSTRUCT_DIR/robust.json -o $RECONSTRUCT_DIR/robust_colorized.ply

# Export from OpenMVG to OpenMVS
echo "Convert to OPENMVS for handover..."
echo "RUN: $OPENMVG_INSTALL_DIR/bin/openMVG_main_openMVG2openMVS -i ./$RECONSTRUCT_DIR/sfm_data.bin -o ./$DEFAULT_OUTPUT_DIR/scene.mvs"
$OPENMVG_INSTALL_DIR/bin/openMVG_main_openMVG2openMVS -i ./$RECONSTRUCT_DIR/sfm_data.bin -o ./$DEFAULT_OUTPUT_DIR/scene.mvs

# Create Dense Point Cloud
echo "OPENMVS Create dense point cloud..."
echo "RUN: $OPENMVS_BUILD_DIR/bin/DensifyPointCloud ./$DEFAULT_OUTPUT_DIR/scene.mvs"
$OPENMVS_BUILD_DIR/bin/DensifyPointCloud ./$DEFAULT_OUTPUT_DIR/scene.mvs

# Create Mesh from Point Cloud
echo "OPENMVS Create mesh..."
echo "RUN: $OPENMVS_BUILD_DIR/bin/ReconstructMesh ./$DEFAULT_OUTPUT_DIR/scene_dense.mvs"
$OPENMVS_BUILD_DIR/bin/ReconstructMesh ./$DEFAULT_OUTPUT_DIR/scene_dense.mvs

# Create textures for PointCloudMesh
echo "OPENMVS Create textures for mesh..."
echo "RUN: $OPENMVS_BUILD_DIR/bin/TextureMesh ./$DEFAULT_OUTPUT_DIR/scene_dense_mesh.mvs"
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
