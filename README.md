# Analysis_Tool



## Adaptive batch size strategy using BigDL
* Referring paper https://arxiv.org/abs/1712.02029

`adaptive_bs.sh` is to use adaptive batch size strategy on Resnet tuning for higher accuracy when conducting training in a large-size cluster. 
### Usage

#### Set properly in `tuning.conf`

##### Set Spark parameters
* Spark parameters
    * MASTER="spark://${master_name}:7077"
    * DEPLOY_MODE="client"
    * EXECUTOR_CORES="44" # set cores of each executor, recommend allocating half cores of each worker
    * NUM_EXECUTORS="16" # set executors number, recommend allocating one executor on one node
    * DRIVER_MEMORY="40g"
    * EXECUTOR_MEMORY="40g"

##### Set model parameters
* Model parameters
    * DEPTH="50" 
    * CLASSES="10" # set class number of image data
    * OPTNET="true"
    * SHORTCUT_TYPE="A"
    * train_class=com.intel.analytics.bigdl.models.resnet.Train

##### Tune the strategy rule in tuning.conf. 
* Hyper-parameter to tune
    * init_lr=0.08 # set initial learning rate, follow lr policy in BigDL, we dont tune lr
    * epoch_init=40 # set initial epoch number
    * epoch_step=20 # set step length for changing epoch
    * MAX_EPOCH=100 # recommend setting max epoch as 100 


