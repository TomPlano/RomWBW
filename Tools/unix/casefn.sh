#!/bin/bash
# given filename on the command line, echo the form of the file that 
# actually can be opened.  this needs to do filesystem case shenanigans
#
# we don't handle files with embedded spaces, a horrible idea anyway
#
# this is a bit slow with lots of files, so there's a cache of the join file
#
pid=.$$
search=/tmp/casefn.search$pid
join=/tmp/casefn.join$pid
in=/tmp/casefn.in$pid
cache=/tmp/casefn.cache

function cleanup {
	rm -f $join $search $in
}

trap cleanup EXIT
cleanup

if [ $# -lt 1 ] ; then
	exit 0
fi

#
# normalize to lower case all input file names
# while building an enumeration of all distinct directories
#
for infn in $* ; do
	dirn=$(dirname $infn)
	df=
	for dl in $dirs ; do
		if [ $dl == $dirn ] ; then
			df=$dl
			break;
		fi
	done
	if [ -z $df ] ; then
		dirs="$dirs $dirn"
	fi
	echo -n $dirn/ >> $in
	basename $infn | tr '[A-Z]' '[a-z]' >> $in
done
sort -u $in > $search

here=$(pwd)

#
# if our cached join list matches our directory list, use it
#
if [ -f $cache ] ; then
	cachedirs="$(head -1 $cache)"
	if [ "$dirs" = "$cachedirs" ] ; then
		tail -n +2 $cache > $join
	else
		rm -f $cache
	fi
fi

#
# build join list of file names and lower case forms
#
if [ ! -f $join ] ; then
	rm -f $in
	for dn in ${dirs[@]} ; do
		cd $here
		cd $dn
		for i in * ; do
			# skip any file names containing a space
			if echo "$i" | grep -sq " " ; then
				continue
			fi
			echo $dn/$(echo "$i" | tr '[A-Z]' '[a-z]')",$dn/$i" >> $in
		done
	done
	sort -t, -k 1,1 $in > $join
	echo "$dirs" > $cache
	cat $join >> $cache
fi

join -t, -o 1.2 $join $search | sort -u > $in
if [ $(wc -l < $in) -gt 0 ] ; then
	cat $in
	exit 0
fi

echo nofile
exit 2
