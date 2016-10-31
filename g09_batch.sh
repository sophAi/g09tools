#!/bin/bash
echo "Usage: g09_batch.sh (100 queue_host num_cores) (for maximal 100 jobs running at the same time)"
echo "Created by Po-Jen (2015/11/27)"
default_qsub_host="mem48"
default_bsub_host="12cpu"
default_qsub_num_cores="12"
default_bsub_num_cores="12"
#waiting=1 will put ended() in the bsub command
waiting=0
# extension of the input file, ex: .inp or .gjf
input_ext=".inp"
#submit="bsub" or "qsub"
command -v bsub >/dev/null && submit="bsub" || submit="qsub"
echo "Perform ${input_ext} files with ${submit}"
echo "If you are using other file extension of input file or other submit system,"
echo "be sure to modify the parameters"
if [ "$1" == "clean" ]; then
    echo -e -n "--> Cleaning the whole directory\n\n"
    rm -rf *_GAUSS_SCRDIR *.running *.queue *.fail
    rm -rf *.bsub *.berr *.blog *_GAUSS_SCRDIR *.running *.queue *.fail
    rm -rf *.qsub *.qerr *.qlog
    exit 0
fi
if [ "$1" == "" ]; then
    max_job=9999
    echo -e -n "Use all input files (max=${max_job})\n"
else
    max_job=$1
    echo -e -n "Maximal job number=${max_job}\n"
fi
if [ "$2" == "" ]; then
    if [ "${submit}" == "qsub" ]; then
        queue_host=${default_qsub_host}
    else
        queue_host=${default_bsub_host}
    fi
else
    queue_host=$2
fi
if [ "$3" == "" ]; then
    if [ "${submit}" == "qsub" ]; then
        num_cores=${default_qsub_num_cores}
    else
        num_cores=${default_bsub_num_cores}
    fi
else
    num_cores=$3
fi
pre_job="none"
run_job_count=0
echo "------------------------------"
grep_cmd="\\${input_ext}"
folder_list=`find * -type d`
folder_list="./ ${folder_list}"
for folder in ${folder_list}
do
    check_gaussian=`echo ${folder}|awk -F '_' '{print $NF}'`
    if [ "${check_gaussian}" == "SCRDIR" ]; then
#        echo -e -n "\n--> Skip $folder\n\n"
        continue
    fi
    inp_num=`ls ${folder} | grep ${grep_cmd}\$ | wc -l`
    if [ "${inp_num}" == "0" ]; then
#        echo -e -n "\n--> No *$input_ext files in $folder... Skip!\n\n"
        continue
    else
        echo -e -n "\n--> Found ${inp_num} inp files in ${folder}\n\n"
    fi
    file_list=`ls ${folder} | grep ${grep_cmd}\$ | sort -V`
    for file_name in ${file_list}
    do
        if [ ${folder} == "./" ]; then
            inp_file=${file_name}
            sub_name=${file_name%$input_ext}
        else
            inp_file=${folder}/${file_name}
            sub_name=${folder}/${file_name%$input_ext}
        fi
        out_file=${sub_name}.out
        queue_file=${sub_name}.queue
        gaussian_scrdir=${sub_name}_GAUSS_SCRDIR
        # Detect non-convergence output file
        test -e ${out_file} && out_exist=1 || out_exist=0
        if [ "${out_exist}" == "1" ]; then
            error_count=`grep 'Erro' ${out_file} | wc -l`
            if [ "${error_count}" != "0" ]; then
                echo "--> Detect Error termination in ${out_file}"
            fi
    	    imaginary_freq_count=`grep 'Frequencies -- ' ${out_file} | awk '{print $3" " $4" "$5}' | grep '-' | wc -l`
            # number_freq for checking the output frequencies, 暫時不使用
            normal_terminate=`grep 'Normal' ${out_file} | wc -l`
            if [ "${imaginary_freq_count}" != "0" ]; then
                echo "--> Detect ${imaginary_freq_count} imaginary frequency in ${out_file}"
            fi
    	    detect_input_orientation=`grep 'Input orientation:' ${out_file} | wc -l`
    	    detect_standard_orientation=`grep 'Standard orientation:' ${out_file} | wc -l`
            total_error_count=$((error_count+imaginary_freq_count))
            check_xyz_exist=$((detect_input_orientation+detect_standard_orientation))
            if [ "${check_xyz_exist}" == "0" ]; then
                echo "--> ${out_file} does not have coordinates... Delete!"
                rm -rf ${out_file}
            elif [ "${total_error_count}" != "0" ] || [ "${normal_terminate}" == "0" ]; then
                echo "--> Rebuild ${inp_file}"
                mv -f ${inp_file} ${inp_file}.fail
                #grep '%nproc=' ${out_file} | cut -b 2- > ${inp_file}
                echo "%NprocShared=${num_cores}" > ${inp_file}
                grep '%mem=' ${out_file} | cut -b 2- >> ${inp_file}
                # Use the original setting from .out file
                # ==================================================================
                grep '#' ${out_file} |head -n 1 | cut -b 2- >> ${inp_file}
                # ==================================================================
                # Or make new setting as below:
                # ==================================================================
#                 echo '# b3lyp/6-31+G* opt freq int=superfinegrid' >> ${inp_file}
#                 echo '# b3lyp/6-31+G* opt freq int=UltraFine' >> ${inp_file}
                # ==================================================================
                echo '' >> ${inp_file}
                echo 'remark here' >> ${inp_file}
                echo '' >> ${inp_file}
                grep 'Charge =' ${out_file} | head -n 1 | awk '{print $3" "$6}' >> ${inp_file}
                atom_num=`grep 'NAtoms=' ${out_file} | head -n 1 | awk '{print $2}'`
                xyz_line=`expr ${atom_num} + 4`
                # Try to extract Input orientation coordinates first. If not, try Standard orientation
    	        if [ "${detect_input_orientation}" == "0" ]; then
                	grep -A ${xyz_line} 'Standard orientation:' ${out_file} |tail -${atom_num} | cut -b 15-20,32- | awk '{print " "$1" "$2" "$3" "$4}' | sed "s/\ 8\ /\ O\ /g" | sed "s/\ 1\ /\ H\ /g" | sed "s/\ 6\ /\ C\ /g" >> ${inp_file}
    	        else
                	grep -A ${xyz_line} 'Input orientation:' ${out_file} |tail -${atom_num} | cut -b 15-20,32- | awk '{print " "$1" "$2" "$3" "$4}' | sed "s/\ 8\ /\ O\ /g" | sed "s/\ 1\ /\ H\ /g" | sed "s/\ 6\ /\ C\ /g" >> ${inp_file}
    	        fi
                echo '' >> ${inp_file}
                mv -f ${out_file} ${out_file}.fail
            fi
        fi
        test -e ${out_file} && job_finished=1 || job_finished=0
        test -e ${out_file}.running && job_running=1 || job_running=0
        test -e ${queue_file} && job_enqueued=1 || job_enqueued=0
        if [ "${run_job_count}" -ge "${max_job}" ]; then
        	echo "--> Reach maximal job number= ${max_job}"
            exit 0;
        fi
        if [ "${job_finished}" == "1" ]; then
    	    echo "--> Detect finished job: ${out_file}... Skip!"
            continue
        fi
        if [ "${job_running}" == "1" ]; then
    	    echo "--> Detect running job: ${out_file}.running... Skip!"
            continue 
        elif [ "${job_enqueued}" == "1" ]; then
            echo "--> Detect enqueued job: ${queue_file}... Skip!"
            continue
        fi
        if [ "${submit}" == "bsub" ]; then 

cat << END_OF_BSUB_CAT > ${sub_name}.bsub
#!/bin/bash
#BSUB -J ${sub_name}${input_ext}
#BSUB -e ${sub_name}.berr
#BSUB -o ${sub_name}.blog
#BSUB -q ${queue_host}
#BSUB -n ${num_cores}
#BSUB -R 'span[hosts=1]'
JOB=${inp_file}
# If the system is large, ex number of basis functions >2000 or atoms > 300, use yes
#large="no"
#setg09=setg09c01
setg09=setg09d01

HERE=`pwd`
USER=`whoami`
JOBDIR=\$HERE/${gaussian_scrdir}
cd \$HERE
rm -rf ${sub_name}.blog
rm -rf ${sub_name}.berr
rm -rf ${sub_name}.out.running
source /pkg/chem/gaussian/\$setg09
export GAUSS_SCRDIR=\$JOBDIR
export KMP_AFFINITY="none"
export KMP_STACKSIZE="128000000"
export MKL_DEBUG_CPU_TYPE=2
mkdir -p \$GAUSS_SCRDIR
rm -rf \$GAUSS_SCRDIR/*
ulimit -s unlimited

if [ "\$large" = "yes" ]
then
export  MKL_DEBUG_CPU_TYPE=2
fi
time \$g09root/g09/g09 < $queue_file > ${out_file}.running

rm -rf \$GAUSS_SCRDIR
mv -f ${out_file}.running ${out_file}
rm -rf ${queue_file}


END_OF_BSUB_CAT
            
            echo "--> Submit ${inp_file}"
            echo -e -n "\n==> "
            cp -rf ${inp_file} ${queue_file}  # For detecting enqueued job
            chmod +x ${sub_name}.bsub 
            if [ "${pre_job}" == "none" ]; then
                bsub < ${sub_name}.bsub
            else
                bsub -w "ended(${pre_job}.inp)" < ${sub_name}.bsub
            fi
            if [ "${waiting}" == 1 ]; then
                pre_job=${sub_name}
            fi
            rm -rf ${sub_name}.bsub
            run_job_count=$((run_job_count+1))
            echo ""
        else

cat << END_OF_QSUB_CAT > ${sub_name}.qsub
#!/bin/bash
#PBS -N ${sub_name}${input_ext}
#PBS -o ${sub_name}.qlog
#PBS -e ${sub_name}.qerr
#PBS -q ${queue_host}
#PBS -l nodes=1:ppn=${num_cores}

JOB=${inp_file}
HERE=`pwd`
USER=`whoami`
JOBDIR=\$HERE/${gaussian_scrdir}
cd \$HERE
rm -rf ${sub_name}.qlog
rm -rf ${sub_name}.qerr
rm -rf ${sub_name}.out.running
#export g09root=/opt/software/g09-a02
#export g09root=/opt/software/g09-d01   # For Gaussian 09 D01 Version
#source ${g09root}/g09/bsd/g09.profile
#export GAUSS_SCRDIR=/lustre/lwork/pjhsu/g09/
#alias g09=${g09root}/g09/g09
#export GAUSS_SCRDIR=\$JOBDIR
#mkdir -p \$GAUSS_SCRDIR
#rm -rf \$GAUSS_SCRDIR/*
export GAUSS_SCRDIR=/tmp

time g09 <  ${queue_file}  >  ${out_file}.running

rm -rf \$GAUSS_SCRDIR
mv -f ${out_file}.running ${out_file}
rm -rf ${queue_file}

END_OF_QSUB_CAT
      
            echo "--> Submit ${inp_file}"
            echo -e -n "\n==> "
            cp -rf ${inp_file} ${queue_file}  # For detecting enqueued job
            chmod +x ${sub_name}.qsub
            if [ "${pre_job}" == "none" ]; then
                qsub ${sub_name}.qsub
            else
                echo "--> Under construction for waiting"
            fi
            if [ "${waiting}" == 1 ]; then
                pre_job=${sub_name}
            fi
            rm -rf ${sub_name}.qsub
            run_job_count=$((run_job_count+1))
            echo ""
        fi
    done
done
