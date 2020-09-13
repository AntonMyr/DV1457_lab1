#!/bin/sh

USAGE="usage: $0 [-n N] (-c|-2|-r|-F|-t) <filename>
-n: Limit the number of results to N
-c: Which IP address makes the most number of connection attempts?
-2: Which address makes the most number of successful attempts?
-r: What are the most common results codes and where do they come
from?
-F: What are the most common result codes that indicate failure (no
auth, not found etc) and where do they come from?
-t: Which IP number get the most bytes sent to them?
<filename> refers to the logfile. If ’-’ is given as a filename, or
no filename is given, then standard input should be read. This
enables the script to be used in a pipeline.
"

if [ $# -lt 1 ] || [ $# -gt 5 ]; then
	# access the usage variable and print out its content to stdout
	echo "$USAGE"
        # terminate shell execution with exit code 1
	exit 1
fi

typeCount=0
argj=0
blacklist=0
while [ $(( (i += 1) <= $#)) -ne 0 ]; do 
    eval "arg=\$$i"
    case $arg in
        -n)
            i=$(( $i+1 ))
            eval "argj=\$$i"
            if ! [ $argj -gt 0 ] 2> /dev/null; then
                echo "Error in argument -n. Expected integer, got $argj"
            fi
            ;;
        -e)
            blacklist=1
            ;;
        -c|-2|-r|-F|-t)
            [ $typeCount -gt 0 ] && echo "Only one of (-c|-2|-r|-F|-t) is allowed" && exit 1
            typeCount=$(( $typeCount + 1 ))
            type=$arg
            ;;
        *)
            filename=$arg
    esac
done

if [ -z $filename ] || [ "$filename" = '-' ]; then
    # read from stdin and assign filename to the user input
    read line
    filename="$line"
fi

connection_attempts() {
    output=`awk '{ print $1 }' $filename\
    | sort -V\
    | uniq -c -d\
    | sort -nr\
    | awk '{print $2, "\t", $1}'`
}

successful_connection_attempts() {
    output=`awk '{print $1, $9 }' $filename\
    | grep -E "([0-9\.]+)\ 2[0-9][0-9]" \
    | sort -V \
    | uniq -c -d \
    | sort -nr \
    | awk '{print $2, "\t", $1}'`
}

most_common_result_codes() {
    result_codes=`awk '{print $9 }' $filename\
    | sort -n \
    | uniq -c -d \
    | sort -nr \
    | awk '{print $2}'\
    `
    
    [ $argj -gt 0 ] 2> /dev/null && result_codes=`echo "$result_codes" | head -$argj`
    
    output=""
    for i in $result_codes
    do
        newOutput=`grep -E "\"*\"\ $i" $filename \
        | awk '{print $1 }'\
        | sort -V \
        | uniq -c -d \
        | sort -nr \
        | awk -v code="$i" '{print code, "\t", $2}'`
        [ $argj -gt 0 ] 2> /dev/null && newOutput=`echo "$newOutput" | head -$argj`
        output="${output}${newOutput}\n\n"
    done
}

most_common_failure_result_codes() {
    result_codes=`awk '{print $9 }' $filename\
    | grep -E "(4|5)[0-9][0-9]" \
    | sort -n \
    | uniq -c -d \
    | sort -nr \
    | awk '{print $2}'\
    `

    [ $argj -gt 0 ] 2> /dev/null && result_codes=`echo "$result_codes" | head -$argj`

    output=""
    for i in $result_codes
    do
        newOutput=`grep -E "\"*\"\ $i" $filename \
        | awk '{print $1 }'\
        | sort -V \
        | uniq -c \
        | sort -nr \
        | awk -v code="$i" '{print $1, "\t", code, "\t", $2}'`
        [ $argj -gt 0 ] 2> /dev/null && newOutput=`echo "$newOutput" | head -$argj`
        output="${output}${newOutput}\n\n"
    done
}

most_bytes_sent() {
    output=`awk '{print $1, "\t", $10}' $filename\
    | sort -k2 -nr\
    | sort -u -k1,1 -V\
    | sort -k2 -nr\
    `
}

# arg1 - Which column contains the ip adresses
# arg2 - The final output
blacklisted_ips() {
    echo "${output}" > tmpfile.txt
    while read p; do
        ipaddr=`echo "$p" | awk -v column="$1" '{print $column}'`
        test=`nslookup ${ipaddr} | awk 'FNR == 1 {print $4}' | grep -oE "[^.]*\.[^.]{1,3}\."`
        domain=`echo "${test%?}"`
        domain=`[ -z ${domain} ] 2> /dev/null && echo "0" || echo "${domain}"`
        domainCheck=`grep -cE ${domain} dns.blacklist.txt`;

        [ ! ${domainCheck} -eq 0 ] 2> /dev/null\
        && newOutput="${newOutput}\n$p\t*Blacklisted!*"\
        || newOutput="${newOutput}\n$p"

    done <tmpfile.txt

    rm tmpfile.txt
    echo "${newOutput}" | tail -n +2
}
# Funktion som tar in vilken column som innehåller ip addresserna.
# Den tar sedan denna column och loopar igenom mot blacklisten.
# Denna funktion sköter också den slutgiltiga utskriften?

case $type in 
    -c)
        connection_attempts
        output=`[ $argj -gt 0 ] 2> /dev/null && echo "${output}" | head -$argj || echo "${output}"`
        if [ $blacklist  -gt 0 ]; then
            blacklisted_ips 1 $output
        else
            echo "${output}"
        fi
        ;;
    -2)
        successful_connection_attempts
        output=`[ $argj -gt 0 ] 2> /dev/null && echo "${output}" | head -$argj || echo "${output}"`
        if [ $blacklist -gt 0 ]; then
            blacklisted_ips 1 $output
        else
            echo "${output}"
        fi
        ;;
    -r)
        most_common_result_codes
        output=`echo "${output}" | head -n -2`
        if [ $blacklist -gt 0 ]; then
            blacklisted_ips 2 $output
        else
            echo "${output}"
        fi
        ;;
    -F)
        most_common_failure_result_codes
        if [ $blacklist -gt 0 ]; then
            blacklisted_ips 1 $output
        else
            echo "${output}"
        fi
        echo "${output}" | head -n -2
        ;;
    -t)
        most_bytes_sent
        output=`echo "${output}" | head -$argj`
        if [ $blacklist -gt 0 ]; then
            blacklisted_ips 1
        else
            echo "${output}"
        fi
        ;;
esac