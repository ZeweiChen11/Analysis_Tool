#/bin/sh

trap "exec 1000>&-;exec 1000<&-;exit 0" 2

mkfifo testfifo1
exec 1000<>testfifo1 # 1000 is a file operator
rm -rf testfifo1

for((n=1;n<=12;n++))
do 
    echo >&1000
done

start=`date "+%s"`

for dir in ./train/n*
do
    for file in $dir/*.JPEG
    do
        read -u1000
        {
            echo $file >> size.log; convert $file -print "Size: %wx%h\n" /dev/null >> size.log
            echo >&1000
        } &
    done
done
wait

end=`date "+%s"`
echo "Time: `expr $end -$start` "
x=`grep Size size.log | awk -F ' |x' '{sum+=$2} END {print sum/NR}'`
y=`grep Size size.log | awk -F ' |x' '{sum+=$3} END {print sum/NR}'`

echo "Average size is $x x $y "

exec 1000>&-
exec 1000<&-
