#!/bin/bash

for shellLib in \
 $(dirname ${BASH_SOURCE[0]})/../lib/bash/bin/aws.func \
 ;
do
 . ${shellLib} && continue
   echo ERROR:${BASH_SOURCE[0]} sourcing shellLib: ${shellLib}  >&2
   sleep 3; exit 1
done

case "$1"  in
  get ) shift; getToken $@
  ;;
  show|delete ) echo sorry, YTDB
  ;;
  * ) echo ERROR: ${BASH_SOURCE[0]} Unknown or missing cmd: $* >&2; exit 1
   ;;

esac
 
