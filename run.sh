#!/bin/bash

HASH=$1
: ${HASH:="master"}
PREFIX=$2
: ${PREFIX:=`date +%s`}

MINUTES=2
REQ_PER_SECOND=1

OUT_DIR="./out"
MEM_FILE="${OUT_DIR}/${PREFIX}-mem.json"
LOAD_RESULTS="${OUT_DIR}/${PREFIX}-load.bin"
LOAD_FILE="${OUT_DIR}/${PREFIX}-load.json"

VEGETA_BIN=''
UNAME=`uname`
if [[ "$UNAME" == 'Linux' ]]
then
	VEGETA_BIN='bin/vegeta-linux-x86_64'
elif [[ "$UNAME" == 'Darwin' ]]
then
	VEGETA_BIN='bin/vegeta-darwin-x86_64'
fi

if [[ -z "$VEGETA_BIN" ]]
then
	echo "Could not find a vegeta binary for ${UNAME}"
	exit 1
fi

mkdir -p $OUT_DIR

npm install

git clone https://github.com/alphagov/spotlight.git

cd spotlight

git checkout $HASH

npm install
grunt build:production

../node_modules/performance-harness/bin/node-perf run --out="../${MEM_FILE}" app/server.js &

PERF_PID=$!

cd ..

$VEGETA_BIN attack -targets=routes -rate=${REQ_PER_SECOND} -duration=${MINUTES}m > ${LOAD_RESULTS} &

ATTACK_PID=$!

while :
do
	sleep 60
	echo "Taking a heap dump"
	kill -s ALRM $PERF_PID
	if `ps cax | grep $ATTACK_PID > /dev/null`
	then
		echo "Still attacking"
	else
		echo "Attack done"
		break
	fi
done

kill -s USR2 $PERF_PID

while :
do
	sleep 5
	if `ps cax | grep $PERF_PID > /dev/null`
	then
		echo "Still winding down"
	else
		echo "Proc dead"
		break
	fi
done

$VEGETA_BIN report -input="${LOAD_RESULTS}" -reporter=json > ${LOAD_FILE}

rm -rf spotlight
