#!/bin/bash
folder_list=`find * -type d`
folder_list="./ $folder_list"
root_dir=`pwd`
for folder in ${folder_list}
do
    cd $folder
    file_list=`ls *.out|sort -n`
    for out_file in ${file_list}
    do
        error_count=`grep 'Erro' $out_file | wc -l`
        if [ "$error_count" != "0" ]; then
            echo "--> Detect Error termination in $out_file"
        fi
        imaginary_freq_count=`grep 'Frequencies -- ' $out_file | awk '{print $3" "$4" "$5}' | grep '-' | wc -l`
        normal_terminate=`grep 'Normal' $out_file | wc -l`
        if [ "$imaginary_freq_count" != "0" ]; then
            echo "--> Detect $imaginary_freq_count imaginary frequency in $out_file"
        fi
        total_error_count=$((error_count+imaginary_freq_count))
        if [ "$total_error_count" != "0" ] || [ "$normal_terminate" == "0" ]; then
            echo "mv $out_file to ${out_file}.fail"
            mv -f $out_file ${out_file}.fail
        fi
    done
    cd $root_dir
done
