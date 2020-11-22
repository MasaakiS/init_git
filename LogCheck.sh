#!/bin/bash

#実行ディレクトリ設定
SCRIPT_DIR=$(cd $(dirname $0); pwd)
#処理ログフルパス設定
log=${SCRIPT_DIR}/LogCheck.log
#初期設定
previous_file_update='00000000000000'
previous_file_last_row='0'
#未知のエラーの場合に出力する文字列
err='ERRORERRORERROR'
#出力ファイルにホスト名を含める場合に利用
hostname=`uname -n`
#grep時の条件ヒット時の前後取得行数設定
grep_get_before_row='1'
grep_get_after_row='10'

#処理対象読み取り
while read row; do
    IFS=$','
    wk_init_array=(${row})
    #チェックファイル(フルパス)
    init_check_ffile=${wk_init_array[0]}
    #抽出条件
    init_conditions=${wk_init_array[1]}
    #出力ファイル(フルパス)
    # ###HOSTNAME###を実際のホスト名に変換
    init_output_ffile=`echo ${wk_init_array[2]}|sed "s/###HOSTNAME###/${hostname}/g"`
    #設定ファイル(フルパス)
    # ###HOSTNAME###を実際のホスト名に変換
    init_conf_ffile=`echo ${wk_init_array[3]}|sed "s/###HOSTNAME###/${hostname}/g"`
    #設定ファイル(拡張子無し)
    conf_file=${init_conf_ffile##*/}
    conf_file=${conf_file%.*}
    #前回実行情報
    previous_conf_file=${conf_file}work.conf
    #Tempファイル
    temp_file=${conf_file}.temp
    
    #監視対象ファイル存在チェック
    if [ ! -f ${init_check_ffile} ]; then
        echo "`date +%Y/%m/%d" "%H:%M:%S` 監視対象ファイル：${init_check_ffile}が存在しません。" |tee -a ${log}
        exit 1
    fi
    #監視設定ファイル存在チェック
    if [ ! -f ${init_conf_ffile} ]; then
        echo "`date +%Y/%m/%d" "%H:%M:%S` 設定ファイル：${init_conf_ffile}が存在しません。" |tee -a ${log}
        exit 1
    fi
    
    #前回処理状況取得
    if [ -f ${SCRIPT_DIR}/${previous_conf_file} ]; then
        #echo "`date +%Y/%m/%d" "%H:%M:%S` 前回処理状況ファイル：${SCRIPT_DIR}/${previous_conf_file}を確認。" |tee -a ${log}
        while read row; do
            IFS=$','
            wk_previous_array=(${row})
            previous_file_update=${wk_previous_array[0]}
            previous_file_last_row=${wk_previous_array[1]}
            echo "${SCRIPT_DIR}/${previous_conf_file}の${previous_file_last_row}行目からチェックします。"|tee -a ${log}
        done < ${SCRIPT_DIR}/${previous_conf_file}
    else
        echo "`date +%Y/%m/%d" "%H:%M:%S` 前回処理状況ファイル：${SCRIPT_DIR}/${previous_conf_file}は存在しません。" |tee -a ${log}
    fi
    
    #対象抽出
    #ここのロジックに関して迷い中。何をもとに変更があったかを検出するのが効率。確実性が高いか？
    #監視ファイルの更新日時分秒を取得
    init_check_ffile_update=`date -r ${init_check_ffile} +%Y%m%d%H%M%S`
    #監視ファイルの行数を取得
    init_check_ffile_last_row=`wc -l ${init_check_ffile}|awk '{print $1}'`

    echo "前回の更新日時:${previous_file_update}"
    echo "現在の更新日時:${init_check_ffile_update}"

    if [ ${init_check_ffile_update} -gt ${previous_file_update} ]; then
        #ファイルローテーションされている可能性がある場合は、先頭からチェック
        if [ ${init_check_ffile_last_row} -lt ${previous_file_last_row} ]; then
            previous_file_last_row='0'
            echo  "`date +%Y/%m/%d" "%H:%M:%S` ${init_check_ffile}ファイルはローテーションされている可能性があるため、先頭からチェックします。" |tee -a ${log}
        fi

        #チェック用tempファイル作成
        #sedは配列に入れるときに改行のみの行があった際に配列がズレるのを防ぐため
        tail -n +${previous_file_last_row} ${init_check_ffile}|\
        grep -E ${init_conditions} -B ${grep_get_before_row} -A ${grep_get_after_row}|\
        sed 's/^$/ /g' > ${temp_file}
        result=${PIPESTATUS[1]}

        #grep結果をチェック
        if [ ${result} = '0' ]; then
            echo  "`date +%Y/%m/%d" "%H:%M:%S` 監視対象ファイル${init_check_ffile}のチェック開始" |tee -a ${log}
            #チェック用一時ファイル行数取得
            temp_file_last_row=`wc -l ${temp_file}|awk '{print $1}'`
            # 区切り文字を改行コードに指定
            IFS=$'\n'
            #チェッック用一次ファイル対象行取得
            temp_file_condition_hit_row_array=(`grep -n -E ${init_conditions} ${temp_file}|awk -F':' '{print $1}'`)
            temp_file_condition_hit_row_array_last_row=${#temp_file_condition_hit_row_array[@]}
            # ファイルを配列に読み込む
            temp_file_all_array=(`cat ${temp_file}`)

            temp_file_all_array_last_row=${#temp_file_all_array[@]}

            #チェックと出力
            for e in ${temp_file_condition_hit_row_array[@]}; do

            echo "==================================チェックメッセージ内容=================================="
            echo ${temp_file_all_array[$((e-1))]}

                #設定ファイル読み込み
                while read conf_row; do

                    #判定フラグ初期化
                    chek_status='0'
                    next='0'

                    IFS=$','
                    wk_conf_array=(${conf_row})
                    #連番
                    conf_no=${wk_conf_array[0]}
                    #出力文字列
                    conf_out_str=${wk_conf_array[1]}
                    #出力文字列
                    conf_conditions=${wk_conf_array[2]}
                    #抽出条件文字列からの相対行数:条件1
                    conf_chek1_row=${wk_conf_array[3]%%:*}
                    #抽出条件文字列からの相対行数:条件1
                    conf_chek1_str=${wk_conf_array[3]#*:}
                    #抽出条件文字列からの相対行数:条件2
                    conf_chek2_row=${wk_conf_array[4]%%:*}
                    #抽出条件文字列からの相対行数:条件2
                    conf_chek2_str=${wk_conf_array[4]#*:}
                    #抽出条件文字列からの相対行数:条件3
                    conf_chek3_row=${wk_conf_array[5]%%:*}
                    #抽出条件文字列からの相対行数:条件3
                    conf_chek3_str=${wk_conf_array[5]#*:}
                    #抽出条件文字列からの相対行数:条件4
                    conf_chek4_row=${wk_conf_array[6]%%:*}
                    #抽出条件文字列からの相対行数:条件4
                    conf_chek4_str=${wk_conf_array[6]#*:}

                    #チェックできる行であることをチェック
                    #このチェックを入れることにより、本来のチェックがかからない可能性があるため、コメント化
                    #if [ $((grep_get_before_row-1)) -lt ${e} -a ${e} -lt $((temp_file_all_array_last_row-grep_get_befor_row)) ]; then
                        #チェック条件チェック
                            #チェック条件1をチェック
                            if [ ${chek_status} = '0' -a ${conf_chek1_str} != '-' ]; then
                                if [ ! "`echo ${temp_file_all_array[$((e-1+conf_chek1_row))]}|grep ${conf_chek1_str}`" ]; then
                                    chek_status='1'
                                fi
                            fi
                            #チェック条件2をチェック
                            if [ ${chek_status} = '0' -a  ${conf_chek2_str} != '-' ]; then
                                if [ ! "`echo ${temp_file_all_array[$((e-1+conf_chek2_row))]}|grep ${conf_chek2_str}`" ]; then
                                    chek_status='1'
                                fi
                            fi
                            #チェック条件3をチェック
                            if [ ${chek_status} = '0' -a  ${conf_chek3_str} != '-' ]; then
                                if [ ! "`echo ${temp_file_all_array[$((e-1+conf_chek3_row))]}|grep ${conf_chek3_str}`" ]; then
                                    chek_status='1'
                                fi
                            fi
                            #チェック条件4をチェック
                            if [ ${chek_status} = '0' -a  ${conf_chek4_str} != '-' ]; then
                                if [ ! "`echo ${temp_file_all_array[$((e-1+conf_chek4_row))]}|grep ${conf_chek4_str}`" ]; then
                                    chek_status='1'
                                fi
                            fi
                    #fi

                    #判定とログ出力処理
                    if [ ${chek_status} = '0' ]; then
                        #チェックパターンにヒットした場合は、設定ファイルの出力文字列を出力して、for文から抜ける
                        echo `date +%Y/%m/%d" "%H:%M:%S` ${conf_no} ${conf_out_str} |tee -a ${init_output_ffile}
                        next='1'
                        break
                    fi

                done < ${init_conf_ffile}

                #フィルタ条件にヒットしていたかをチェック
                if [ ${next} = '1' ]; then
                    next='0'
                else
                    #最終まで処理していたら、パターンにマッチしていないのでエラーメッセージを出力
                    echo "`date +%Y/%m/%d" "%H:%M:%S` ${err} ${temp_file_all_array[$((e-1))]}"  |tee -a ${init_output_ffile}
                fi

            done

            #終了処理
            echo "${init_check_ffile_update},${init_check_ffile_last_row}" > ${previous_conf_file}
            echo  "`date +%Y/%m/%d" "%H:%M:%S` 監視対象ファイル${init_check_ffile}のチェック完了" |tee -a ${log}
        else
            echo  "`date +%Y/%m/%d" "%H:%M:%S` 監視対象ファイル${init_check_ffile}の新たなエラー出力はありませんでした。" |tee -a ${log}
        fi

    else
        echo "`date +%Y/%m/%d" "%H:%M:%S` 監視対象ファイル${init_check_ffile}の変更はありませんでした。" |tee -a ${log}
    fi

IFS=$','    
done < ${SCRIPT_DIR}/LogCheckInit.conf
