#!/bin/bash
 
# source the ciop functions (e.g. ciop-log)
source ${ciop_job_include}

# define the exit codes
SUCCESS=0
ERR_INVALIDFORMAT=2
ERR_NOIDENTIFIER=5
ERR_NODEM=7

# add a trap to exit gracefully
function cleanExit ()
{
local retval=$?
local msg=""
case "$retval" in
$SUCCESS)           msg="Processing successfully concluded";;
$ERR_INVALIDFORMAT) msg="Invalid format must be roi_pac or gamma";;
$ERR_NOIDENTIFIER)  msg="Could not retrieve the dataset identifier";;
$ERR_NODEM)         msg="DEM not generated";;
*) msg="Unknown error";;
esac
[ "$retval" != "0" ] && ciop-log "ERROR" "Error $retval - $msg, processing aborted" || ciop-log "INFO" "$msg"
exit $retval
}
trap cleanExit EXIT
 
export PATH=/opt/anaconda/bin:/application/srtmdem/bin:$PATH 
export DISPLAY=:99.0

srtm_path="/tmp/srtm1arcsecond/"

# retrieve the DEM format to generate
format="`ciop-getparam format`"

case $format in
  roi_pac)
    option="";;
  gamma)
    option="-g";;
  *)
    exit $ERR_INVALIDFORMAT;;
esac

# read the catalogue reference to the dataset
while read inputfile
do
  UUIDTMP="/tmp/`uuidgen`"
  mkdir $UUIDTMP
  cd $UUIDTMP

  # SRTM.py uses matplotlib, set a temporary directory
  export MPLCONFIGDIR=$UUIDTMP/

  ciop-log "INFO" "Working on $inputfile in $UUIDTMP" 

  dem_name=`uuidgen`
  [ -z "$dem_name" ] && exit $ERR_NOIDENTIFIER 

  wkt="$( opensearch-client "$inputfile" wkt | tail -1 )"
  ciop-log "DEBUG" "wkt is $wkt"

  # invoke the SRTM.py
  # the folder /application/SRTM/data contains the SRTM tiles in tif format
  bbox=$( mbr "$wkt" )
  ciop-log "INFO" "Generating DEM covering ${bbox}"
  SRTM.py $( echo ${bbox} | tr "," " " ) $UUIDTMP/$dem_name -D ${srtm_path} $option 1>&2
  [ ! -e $UUIDTMP/$dem_name.dem ] && exit $ERR_NODEM
  
  # save the bandwidth
  ciop-log "INFO" "Compressing DEM"
  tar cfz $dem_name.dem.tgz $dem_name*
 
  # have the compressed archive published and its reference exposed as metalink
  ciop-log "INFO" "Publishing results"
  ciop-publish -m $UUIDTMP/$dem_name.dem.tgz  
   
  # clean-up for the next dataset reference
  rm -fr $UUIDTMP
   
done
