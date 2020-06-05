# Main Workflow - CP project analysis
#
# Contributors: @aiswaryaprasad

# --- Importing Some Packages --- #
from os import walk, rename, makedirs
from os.path import join, exists
from snakemake.shell import shell
import matplotlib.pyplot as plt
import numpy as np
from matplotlib import rc
import pandas as pd

# --- Defining Some Functions --- #
def checkForGuppyLog(path):
    for dirpath, dirlist, filenames in walk(path):
        for name in filenames:
            if name.endswith('.log'):
                return True
    return False

# find run and barcode for given sample ID using
# returns path to fastq "{runName}/barcode{barcode}.fastq"
def findSampleFastq(wildcards):
    sampleDict = config['sample_dict']
    runBarcodeDict = {}
    for runName in sampleDict:
        for barcode in sampleDict[runName]:
            if sampleDict[runName][barcode] == wildcards:
                runBarcodeDict = {'runName': runName, 'barcode': barcode}
                return join("qcat_trimmed", runBarcodeDict['runName'], "barcode"+runBarcodeDict['barcode']+".fastq")

# can also be a directory with multiple seq summary files for the same input
# modify function accordingly esp for interrupted basecalling
def findSeqSummary(wildcards):
    return join("guppy_output", wildcards, "sequencing_summary.old.txt")

# --- Importing Configuration File and Defining Important Lists --- #
configfile: "config.yaml"
# information to be obtained from config file
ListOfExpectedBarcodes = []
confDict = config['sample_dict']
for RunName in confDict:
    for barCode in confDict[RunName].keys():
        ListOfExpectedBarcodes.append(join("qcat_trimmed", RunName, "barcode"+barCode+".fastq"))

# --- The rules --- #

rule all:
    input:
        #--> for basecalling
        expand(join("fastq", "{runnames}.fastq"), runnames=config['runnames']),
        #--> runQC
        expand(join("QC", "runs", "{runnames}", "{runnames}_NanoStats.txt"), runnames=config['runnames']),
        #--> demultiplex_trim
        # expand(join("qcat_trimmed", "{runnames}"), runnames=config['runnames']),
        #--> summary
        expand(join(config['ROOT'], "qcat_trimmed", "{runnames}", "summary.txt"), runnames=config['runnames']),
        #--> collectSamples
        # expand(join("fastq", "samples", "{samples}.fastq.gz"), samples=config['samples']),
        #--> sampleQC
        expand(join("QC", "samples", "{samples}", "{samples}_NanoPlot-report.html"), samples=config['samples']),
        #--> kraken2
        expand(join("classified", "{samples}", "kraken2_Minidb", "result"), samples=config['samples']),
        # uncomment if using
        # expand(join("classified", "{samples}", "kraken2_humandb", "result"), samples=config['samples']),
        # expand(join("classified", "{samples}", "kraken2_custom", "result"), samples=config['samples']),
        #--> bracken
        expand(join("classified", "{samples}", "bracken", "species_report"), samples=config['samples']),
        expand(join("classified", "{samples}", "bracken", "genus_report"), samples=config['samples']),
        #--> centrifuge
        expand(join("classified", "{samples}", "centrifuge", "report"), samples=config['samples'])
    threads: 8


rule basecalling:
    input:
        raw_dir=join(config['RAWDIR'], "{runnames}/")
    output:
        run_fastq=join("fastq", "{runnames}.fastq")
    run:
        # if recursive is enabled, I can give the run dir which has sub runs..(Expt 4) (--min_qscore 7 is already default)
        # conditionally allow for --resume figure out how later
        # there is a recent issue April2020 with barcode trimming in guppy_basecaller so use qcat for demult
        # dna_r9.4.1_450bps_hac.cgf for FLO-MIN106 and SQK-LSK109 combination
        guppy_output_dir = join("guppy_output", wildcards.runnames)
        try:
            makedirs(guppy_output_dir)
        except FileExistsError:
            flag = checkForGuppyLog(guppy_output_dir)
            pass
        else:
            flag = False
        args = {
        "input":input.raw_dir,
        "output_dir":guppy_output_dir
        }
        command = "guppy_basecaller --resume --input_path {input} --save_path {output_dir} --flowcell FLO-MIN106 --kit SQK-LSK109 --recursive --records_per_fastq 0 --calib_detect --qscore_filtering"
        command = command.format(**args)
        if flag:
           shell(command)
           for dirpath, dirlist, filenames in walk(join(guppy_output_dir, wildcards.runnames)):
               for name in filenames:
                   if name.endswith('.fastq'):
                       rename(join(dirpath, name), join(dirpath, wildcards.runnames+".fastq"))
           try:
               shell("cat "+guppy_output_dir+"/pass/*.fastq > fastq/"+wildcards.runnames+".fastq")
           except:
               print("no basecalling happened")
               shell("touch "+"fastq"+"/"+wildcards.runnames+".fastq")
        else:
            print("No log file to resume from. Starting fresh instance of basecallig")
            command = "guppy_basecaller --input_path {input} --save_path {output_dir} --flowcell FLO-MIN106 --kit SQK-LSK109 --recursive --records_per_fastq 0 --calib_detect --qscore_filtering"
            command = command.format(**args)
            shell(command)
            for dirpath, dirlist, filenames in walk(join(guppy_output_dir, wildcards.runnames)):
                for name in filenames:
                    if name.endswith('.fastq'):
                        rename(join(dirpath, name), join(dirpath, wildcards.runnames+".fastq"))
            try:
                shell("cat "+guppy_output_dir+"/pass/*.fastq > fastq/"+wildcards.runnames+".fastq")
            except:
                print("no basecalling happened")
                shell("touch "+"fastq"+"/"+wildcards.runnames+".fastq")
#
# remove empty fastq files to avoid errors later
#
# For run1 no seq summary into output dir copying MinionQC results. Skip Nanocomp QC.
# For run4 considering only first section (> 1/2 of the data) of run other section basecalled as seperate set
# find sequencing summary
rule runQC:
    input:
        seq_summary=lambda wildcards: findSeqSummary(wildcards.runnames)
    output:
        # MinionQC_out=directory(join("QC", "runs", "MinionQC", "{runnames}")),
        # NanoStat_out=join("QC", "runs", "NanoStat", "{runnames}"),
        Nanoplot_Dynamic_Histogram_Read_length_html = join("QC", "runs", "{runnames}", "{runnames}_Dynamic_Histogram_Read_length.html"),
        Nanoplot_HistogramReadlength_png = join("QC", "runs", "{runnames}", "{runnames}_HistogramReadlength.png"),
        Nanoplot_LengthvsQualityScatterPlot_dot_png = join("QC", "runs", "{runnames}", "{runnames}_LengthvsQualityScatterPlot_dot.png"),
        Nanoplot_LengthvsQualityScatterPlot_kde_png = join("QC", "runs", "{runnames}", "{runnames}_LengthvsQualityScatterPlot_kde.png"),
        Nanoplot_LogTransformed_HistogramReadlength_png = join("QC", "runs", "{runnames}", "{runnames}_LogTransformed_HistogramReadlength.png"),
        Nanoplot_report_html = join("QC", "runs", "{runnames}", "{runnames}_NanoPlot-report.html"),
        Nanoplot_NanoStats_txt = join("QC", "runs", "{runnames}", "{runnames}_NanoStats.txt"),
        Nanoplot_Weighted_HistogramReadlength_png = join("QC", "runs", "{runnames}", "{runnames}_Weighted_HistogramReadlength.png"),
        Nanoplot_Weighted_LogTransformed_HistogramReadlength_png = join("QC", "runs", "{runnames}", "{runnames}_Weighted_LogTransformed_HistogramReadlength.png"),
        Nanoplot_Yield_By_Length_png = join("QC", "runs", "{runnames}", "{runnames}_Yield_By_Length.png")
    run:
        args = {
        "input":input.seq_summary,
        "outputNanoP":join("QC", "runs", wildcards.runnames),
        "prefix": wildcards.runnames+"_"
        }
        command_nanoP = "NanoPlot --summary {input} --outdir {outputNanoP} -p {prefix} --readtype 1D"
        shell(command_nanoP.format(**args)+" || touch {output}")
#
# qcat does trimming simultaneaously if untrimmed files are needed specifically, edit demultiplex_keep_trim
rule demultiplex_trim:
    input:
        raw_fastq=expand("fastq/{runnames}.fastq", runnames=config['runnames'])
    output:
        trimmed=ListOfExpectedBarcodes,
        # tsv=join("qcat_trimmed", "{runnames}.tsv")
    run:
        args = {
        "input":input.raw_fastq,
        "outputTrimmed":join(config['ROOT'], "qcat_trimmed", wildcards.runnames),
        "kit":config['barcode_kit'],
        "tsvPath":join(config['ROOT'], "qcat_trimmed", wildcards.runnames)
        }
        command = "qcat --fastq {input} --barcode_dir {outputTrimmed} --trim -k {kit} --detect-middle --tsv > {tsvPath}.tsv"
        command = command.format(**args)
        shell(command)

rule demultiplex_summary:
    input:
        trimmed=ListOfExpectedBarcodes,
        # tsv=join("qcat_trimmed", "{runnames}.tsv")
    output:
        txt=join(config['ROOT'], "qcat_trimmed", "{runnames}", "summary.txt"),
        png=join(config['ROOT'], "qcat_trimmed", "{runnames}", "summary.png")
    script:
        "scripts/demultiplex_summarize.py"


############################################################################################################
# BELOW RULE DOES NOT WORK AT ALL. IMPLEMENT ONLY IF NEEDED
############################################################################################################
# qcat does trimming simultaneaously so uncomment demultiplex_keep_trim
# if untrimmed files are needed specifically
# BARCODES=[01,02,...]
# rule demultiplex_keep_trim:
#     input:
#         raw_fastq="fastq/{qcat_test_name}.fastq"
#     output:
#         demux_dir=directory(join(config['ROOT'], "qcat_output/demuxd", "{qcat_test_name}")),
#         trimmed_dir=directory(join(config['ROOT'], "qcat_output/trimmed", "{qcat_test_name}"))
#     run:
#         args = {
#         "input":join(output.demux_dir, {qcat_test_name}),
#         # "outputDemux":output.demux_dir,
#         "outputTrimmed":output.trimmed_dir,
#         "kit":config['barcode_kit']
#         }
#         command = "qcat --fastq {input} --barcode_dir {outputTrimmed} -k {kit} --detect-middle"
#         command = command.format(**args)
#         shell(command)
#
#         command = "qcat --fastq {input} --trim -k {kit} --detect-middle"
# Run 0 (sample 01) trimmed in qcat seperately. Will be combined from this point on
############################################################################################################
############################################################################################################
# move to config
# dict of sample name and barcode (called sampleDict) in each run
# X:
#  'barcode': 'sample ID'}
# added to config (X is 0 to 4 for run number)
#
#
rule collectSamples:
    input:
        fastqPath=lambda wildcards: findSampleFastq(wildcards.samples)
    output:
        fastq=join("fastq", "samples", "{samples}.fastq.gz"),
    run:
        try:
            makedirs(join("fastq", "samples"))
        except FileExistsError:
            pass
        if exists(input.fastqPath):
            print("\n {} file exists".format(input.fastqPath))
            shell("cat "+input.fastqPath+" > "+join("fastq", "samples", wildcards.samples+".fastq"))
        else:
            print("\n {} NO file exists".format(input.fastqPath))
            shell("touch "+input.fastqPath)
        # zips all files. Unxip as needed for further use
        shell("gzip "+join("fastq", "samples", wildcards.samples+".fastq"))
#
# QC of fastq files
rule sampleQC:
    input:
        sampleFastq=join("fastq", "samples", "{samples}.fastq.gz")
    output:
        Nanoplot_Dynamic_Histogram_Read_length_html = join("QC", "samples", "{samples}", "{samples}_Dynamic_Histogram_Read_length.html"),
        Nanoplot_HistogramReadlength_png = join("QC", "samples", "{samples}", "{samples}_HistogramReadlength.png"),
        Nanoplot_LengthvsQualityScatterPlot_dot_png = join("QC", "samples", "{samples}", "{samples}_LengthvsQualityScatterPlot_dot.png"),
        Nanoplot_LengthvsQualityScatterPlot_kde_png = join("QC", "samples", "{samples}", "{samples}_LengthvsQualityScatterPlot_kde.png"),
        Nanoplot_LogTransformed_HistogramReadlength_png = join("QC", "samples", "{samples}", "{samples}_LogTransformed_HistogramReadlength.png"),
        Nanoplot_report_html = join("QC", "samples", "{samples}", "{samples}_NanoPlot-report.html"),
        Nanoplot_NanoStats_txt = join("QC", "samples", "{samples}", "{samples}_NanoStats.txt"),
        Nanoplot_Weighted_HistogramReadlength_png = join("QC", "samples", "{samples}", "{samples}_Weighted_HistogramReadlength.png"),
        Nanoplot_Weighted_LogTransformed_HistogramReadlength_png = join("QC", "samples", "{samples}", "{samples}_Weighted_LogTransformed_HistogramReadlength.png"),
        Nanoplot_Yield_By_Length_png = join("QC", "samples", "{samples}", "{samples}_Yield_By_Length.png")
    run:
        args = {
            "input":input.sampleFastq,
            "output_plot":join("QC", "samples", wildcards.samples),
            "name":wildcards.samples,
            "prefix":wildcards.samples+'_'
        }
        command = "NanoPlot --verbose --fastq {input} --outdir {output_plot} --prefix {prefix}"
        shell(command.format(**args))
#
#
rule filterSamples:
    input:
        input=join("fastq", "samples", "{samples}.fastq.gz")
    output:
        output7=join("fastq", "samples_Q7", "{samples}.fastq.gz"),
        output10=join("fastq", "samples_Q10", "{samples}.fastq.gz")
    run:
        args = {
        "output7":output.output7,
        "output10":output.output10
        }
        makedirs(output.output7)
        makedirs(output.output10)
        command7 = "gunzip -c {input} | NanoFilt --quality 7 | gzip > {output7}"
        shell(command7.format(**args))
        command10 = "gunzip -c {input} | NanoFilt --quality 10 | gzip > {output7}"
        shell(command10.format(**args))
#
# uncomment if using
# rule kraken2_human:
#     input:
#         fastq=join("fastq", "samples_Q7", "{samples}.fastq.gz")
#     output:
#         report=join("classified", "{samples}", "kraken2_humandb", "report"),
#         result=join("classified", "{samples}", "kraken2_humandb", "result"),
#         unclass=join("classified", "{samples}", "kraken2_humandb", "unclassified")
#     run:
#         args = {
#         "db": "/"+join("media", "utlab", "DATA_HDD1", "Nanopore_metagenomics", "Softwares_for_analysis", "kraken2", "dbs", "db_humanVec_May2020")+"/",
#         "t": 8,
#         "input": input.fastq,
#         "output_report": output.report,
#         "output_result": output.result,
#         "output_unclass": output.unclass,
#         }
#         command = "kraken2 --db {db} --confidence 0.75 --threads {t}  --gzip-compressed {input} --report {output_report} --report-zero-counts --output {output_result} --unclassified-out {output_unclass}"
#         shell(command.format(**args))
#
############################################################################################################
############################################################################################################
# the version of rule kraken2_human that has been commented out can be used
# when unclassified reads from it need to be used by other rule
# if using replace input of rule kraken2_custom, kraken2 and Centrifuge with,
# rules.kraken2_human.output.unclass and change argument inside the rule for command as needed
# rule kraken2_human:
#     input:
#         fastq=join("fastq", "samples", "{samples}.fastq.gz")
#     output:
#         report=join("classified", "{samples}", "kraken2_humandb", "report"),
#         result=join("classified", "{samples}", "kraken2_humandb", "result"),
#         unclass=join("classified", "{samples}", "kraken2_humandb", "unclassified")
#     run:
#         args = {
#         "db": "/"+join("media", "utlab", "DATA_HDD1", "Nanopore_metagenomics", "Softwares_for_analysis", "kraken2", "dbs", "db_humanVec_May2020")+"/",
#         "t": 8,
#         "input": input.fastq,
#         "output_report": output.report,
#         "output_result": output.result,
#         "output_unclass": output.unclass,
#         }
#         command = "kraken2 --db {db} --confidence 0.75 --threads {t}  --gzip-compressed {input} --report {output_report} --report-zero-counts --output {output_result} --unclassified-out {output_unclass}"
#         shell(command.format(**args))
############################################################################################################
############################################################################################################
#
# rule kraken2_custom:
#     input:
#         fastq=join("fastq", "samples_Q7", "{samples}.fastq.gz")
#     output:
#         report=join("classified", "{samples}", "kraken2_BacArchViFunProt", "report"),
#         result=join("classified", "{samples}", "kraken2_BacArchViFunProt", "result")
#     run:
#         args = {
#         "db": "/"+join("media", "utlab", "DATA_HDD1", "Nanopore_metagenomics", "Softwares_for_analysis", "kraken2", "dbs", "db_BacArchViFunProt_May2020")+"/",
#         "t": 8,
#         "input": input.fastq,
#         "output_report": output.report,
#         "output_result": output.result
#         }
#         command = "kraken2 --db {db} --confidence 0.75 --threads {t}  --gzip-compressed {input} --report {output_report} --report-zero-counts --output {output_result}"
#         shell(command.format(**args))
#
rule kraken2:
    input:
        fastq=join("fastq", "samples_Q7", "{samples}.fastq.gz")
    output:
        # report_mpa=join("classified", "{samples}", "kraken2_Minidb", "report_mpa"),
        report=join("classified", "{samples}", "kraken2_Minidb", "report"),
        result=join("classified", "{samples}", "kraken2_Minidb", "result"),
    run:
        args = {
        "db": config['kraken_db'],
        "t": 8,
        "input": input.fastq,
        # "output_reportmpa": output.report_mpa,
        "output_report": output.report,
        "output_result": output.result,
        }
        commandMPA = "kraken2 --db {db} --confidence ? --threads {t}  --gzip-compressed {input} --report {output_reportmpa} --report-zero-counts --use-mpa-style > /dev/null"
        command = "kraken2 --db {db} --confidence 0.00001 --threads {t}  --gzip-compressed {input} --report {output_report} --report-zero-counts --output {output_result}"
        # shell(commandMPA.format(**args))
        shell(command.format(**args))
#
#
rule bracken:
    input:
        kraken_report=rules.kraken2.output.report
    output:
        reportS=join("classified", "{samples}", "bracken", "species_report"),
        reportG=join("classified", "{samples}", "bracken", "genus_report")
    run:
        args = {
        "db": config['kraken_db'],
        "input": input.kraken_report,
        "output_reportS": output.reportS,
        "output_reportG": output.reportG
        }
        commandS = "bracken -d {db} -i {input} -l S -o {output_reportS}"
        commandG = "bracken -d {db} -i {input} -l G -o {output_reportG}"
        shell(commandS.format(**args))
        shell(commandG.format(**args))
#
#
rule centrifuge:
    input:
        fastq=join("fastq", "samples_Q7", "{samples}.fastq.gz")
    output:
        report=join("classified", "{samples}", "centrifuge", "report"),
        result=join("classified", "{samples}", "centrifuge", "result")
    run:
        args = {
        "input": input.fastq,
        "db": config['centrifuge_db'],
        "output_report": output.report,
        "output_result": output.result
        }
        # -U - means take from stdin
        command = "gunzip -c {input} | centrifuge -x {db} -q  -U - --report-file {output_report} -S {output_result}"
        shell(command.format(**args))
#
# Dir structure of output of above 4 rules
# classified
# └── <sample#>
#     ├── bracken
#     │   ├── genus_report
#     │   └── species_report
#     ├── centrifuge
#     │   ├── report
#     │   └── result
#     ├── kraken2_BacArchViFunProt
#     │   ├── report
#     │   └── result
#     ├── kraken2_humandb
#     │   ├── report
#     │   ├── result
#     │   └── unclassified
#     └── kraken2_Minidb
#         ├── report
#         └── result
###########--comparative analysis--##########
# rule compare:
#     input:
#         reports, results
#     output:
#         figure
#     script:
#         r
#         py
