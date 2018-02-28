#!/bin/sh
set -e
cur_dir=$(cd "$(dirname "$0")"; pwd)
root_dir=${cur_dir}/../../../
#source ${root_dir}/conf/config
source ${cur_dir}/../conf/engineSettings.conf
source ./tuning.conf
if [ ! -f ${cur_dir}/bigdl*.log ]; then
    echo "No bigdl*.log exists in current dir!"
else
    mv ${cur_dir}/bigdl*.log /tmp/
fi

# step_num = (MAX_EPOCH - epoch_init) / epoch_step [round up]
step_num=`echo "a=$((${MAX_EPOCH} - ${epoch_init})); b=${epoch_step}; if ( a%b ) a/b+1 else a/b" | bc`

TOTAL_EXECUTOR_CORES=$((${EXECUTOR_CORES} * ${NUM_EXECUTORS}))
bs_init=$((${TOTAL_EXECUTOR_CORES} * 2)) # recommend to use double cores as the initial batch size

#get the bs_max
bs_max=${bs_init}
for i in `seq ${step_num}`
do 
    bs_max=$((${bs_max} * 2))   # double every epoch_step
done
echo "bs_max: ${bs_max}"

#check if checkpoint folder exists and clean its contents
if [ ! -d ${CHECK_POINT_FOLDER} ]; then
    echo "check point dir does not exist, make it..."
    mkdir -p ${CHECK_POINT_FOLDER}
else
    echo "check point dir exists, clean it..."
    rm -rf ${CHECK_POINT_FOLDER}/*
fi

spark-submit \
    --master ${MASTER} \
    --deploy-mode ${DEPLOY_MODE} \
    --executor-cores ${EXECUTOR_CORES} \
    --total-executor-cores ${TOTAL_EXECUTOR_CORES} \
    --driver-memory ${DRIVER_MEMORY}  \
    --executor-memory ${EXECUTOR_MEMORY}  \
    --driver-class-path ${BIGDL_HOME}/dist/lib/bigdl-*-jar-with-dependencies.jar \
    --class ${train_class} \
    ${BIGDL_HOME}/dist/lib/bigdl-*-jar-with-dependencies.jar \
    --batchSize ${bs_init} \
    -f ${TRAINING_DATA_DIR} \
    --optnet ${OPTNET} \
    --depth ${DEPTH} \
    --classes ${CLASSES} \
    --shortcutType ${SHORTCUT_TYPE} \
    --learningRate ${init_lr} \
    --cache ${CHECK_POINT_FOLDER} \
    --nEpochs ${epoch_init} 
mv ${cur_dir}/bigdl.log ${cur_dir}/bigdl_p0.log
#summary log
echo "------------<Adaptive BS Tuning Result>------------" | tee -a ${cur_dir}/adaptive_analysis.log
echo "====part 0 : 1~${epoch_init} epochs ===" | tee -a ${cur_dir}/adaptive_analysis.log
echo "Batch size: `grep Through ${cur_dir}/bigdl_p0.log | head -1 | awk -F ' |]' '{print $17}'`" | tee -a ${cur_dir}/adaptive_analysis.log
echo "Iteration: `grep Through ${cur_dir}/bigdl_p0.log | wc -l`" | tee -a ${cur_dir}/adaptive_analysis.log
echo "Average training throughput (images/sec): `grep Through ${cur_dir}/bigdl_p0.log | awk -F ' |]' '{sum+=$24} END {print sum/NR}'`" | tee -a ${cur_dir}/adaptive_analysis.log
t=`grep Through ${cur_dir}/bigdl_p0.log | tail -1 | awk -F ' |s' '{print $13}'`
total_wall_clock=${t}
echo "Time to train (sec): ${t} "| tee -a ${cur_dir}/adaptive_analysis.log
echo "Top1 Accuracy: `grep Accuracy ${cur_dir}/bigdl_p0.log | tail -1 |awk -F ' |)' '{print $14}'`" | tee -a ${cur_dir}/adaptive_analysis.log

bs_cur=${bs_init}
epoch_cur=${epoch_init}
for j in `seq ${step_num}`
do 
    bs_cur=$((${bs_cur} * 2))
    epoch_cur=$((${epoch_cur} + ${epoch_step}))
    latest_ck_dir=`ls -td -- ${CHECK_POINT_FOLDER}/* | head -1`
    latest_ck_num=`ls -t ${latest_ck_dir} | head -1 | cut -b 13-`
    spark-submit \
        --master ${MASTER} \
        --deploy-mode ${DEPLOY_MODE} \
        --executor-cores ${EXECUTOR_CORES} \
        --total-executor-cores ${TOTAL_EXECUTOR_CORES} \
        --driver-memory ${DRIVER_MEMORY}  \
        --executor-memory ${EXECUTOR_MEMORY}  \
        --driver-class-path ${BIGDL_HOME}/dist/lib/bigdl-*-jar-with-dependencies.jar \
        --class ${train_class} \
        ${BIGDL_HOME}/dist/lib/bigdl-*-jar-with-dependencies.jar \
        --batchSize ${bs_cur} \
        -f ${TRAINING_DATA_DIR} \
        --optnet ${OPTNET} \
        --depth ${DEPTH} \
        --classes ${CLASSES} \
        --shortcutType ${SHORTCUT_TYPE} \
        --learningRate ${init_lr} \
        --cache ${CHECK_POINT_FOLDER} \
        --nEpochs ${epoch_cur} \
        --state ${latest_ck_dir}/optimMethod.${latest_ck_num} \
        --model ${latest_ck_dir}/model.${latest_ck_num}
    mv ${cur_dir}/bigdl.log ${cur_dir}/bigdl_p${j}.log
    echo "====part ${j} : $((${epoch_cur} - ${epoch_step})) ~ ${epoch_cur} epochs ===" | tee -a ${cur_dir}/adaptive_analysis.log
    echo "Batch size: `grep Through ${cur_dir}/bigdl_p${j}.log | head -1 | awk -F ' |]' '{print $17}'`" | tee -a ${cur_dir}/adaptive_analysis.log
    echo "Iteration: `grep Through ${cur_dir}/bigdl_p${j}.log | wc -l`" | tee -a ${cur_dir}/adaptive_analysis.log
    echo "Average training throughput of part ${j} : `grep Through ${cur_dir}/bigdl_p${j}.log | awk -F ' |]' '{sum+=$24} END {print sum/NR}'`" | tee -a ${cur_dir}/adaptive_analysis.log
    t=`grep Through ${cur_dir}/bigdl_p${j}.log | tail -1 | awk -F ' |s' '{print $13}'`
    total_wall_clock=$(echo "${total_wall_clock} + ${t}" | bc)
    echo "Time to train (sec): ${t}"| tee -a ${cur_dir}/adaptive_analysis.log
    echo "Top1 Accuracy: `grep Accuracy ${cur_dir}/bigdl_p${j}.log | tail -1 |awk -F ' |)' '{print $14}'`" | tee -a ${cur_dir}/adaptive_analysis.log

done
echo "----------------------<TOTAL>---------------------" >> ${cur_dir}/adaptive_analysis.log
echo "Average Training Throughput: `grep Throughput ${cur_dir}/bigdl_p*.log | awk -F ' |]' '{sum+=$24} END {print sum/NR}'`" >> ${cur_dir}/adaptive_analysis.log
echo "Total time to train: ${total_wall_clock}" >> ${cur_dir}/adaptive_analysis.log
echo "Final Top1 Accuracy: `grep Accuracy ${cur_dir}/bigdl_p${step_num}.log | tail -1 |awk -F ' |)' '{print $14}'`" >> ${cur_dir}/adaptive_analysis.log
cat ${cur_dir}/adaptive_analysis.log | tail -n $((${step_num} * 6 + 11))
