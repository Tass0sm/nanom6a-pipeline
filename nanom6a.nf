#!/usr/bin/env nextflow

// genome fasta file for mapping
Channel
    .fromPath(params.genome_fasta, checkIfExists:true)
    .into{ samtools_genome_fasta;
           picard_genome_fasta;
           extraction_genome_fasta;
           prediction_genome_fasta }

// reference transcripts sequence fasta file
Channel
    .fromPath(params.reference_fasta, checkIfExists:true)
    .into{ tombo_reference_fasta; prediction_reference_fasta }

// gene to reference transcripts information
Channel
    .fromPath(params.isoform_file, checkIfExists:true)
    .set{ isoform_file }

// A directory of single read fast5s
Channel
    .fromPath(params.fast5_dir, checkIfExists:true)
    .set{ fast5_dir }

process tombo_resquiggle {
  publishDir "${params.resultsDir}/", mode: 'copy'
  input:
      path(fast5_dir)
      path(reference_fasta) from tombo_reference_fasta
  output:
      file fast5_dir into listing_resquiggle_output, extraction_resquiggle_output

  script:
    """
    module load python
    source activate tombo-env
    tombo resquiggle ${fast5_dir} \
        ${reference_fasta} \
        --processes ${task.cpus} \
        --fit-global-scale \
        --include-event-stdev \
        --overwrite
    """
}

process list_fast5s {
  publishDir "${params.resultsDir}/", mode: 'copy'
  input:
      file(resquiggled_fast5s) from listing_resquiggle_output
  output:
      file "files.txt" into list_fast5s_output_extraction, list_fast5s_output_prediction

  script:
  """
  find -L ${resquiggled_fast5s} -name "*.fast5" > "files.txt"
  """
}

process picard_create_seq_dict {
  publishDir "${params.resultsDir}/", mode: 'copy'
  input:
    file(genome_fasta) from picard_genome_fasta

  output:
    file("output.dict") into picard_output

  script:
  def jar_file_path = "/users/PAS1405/tassosm/Work/picard/build/libs/picard.jar"
  """
  java -jar ${jar_file_path} CreateSequenceDictionary \
        R=${genome_fasta} \
        O="output.dict"
  """
}

process samtools_index {
  publishDir "${params.resultsDir}/", mode: 'copy'
  input:
    file(genome_fasta) from samtools_genome_fasta
  output:
    file("*.fai") into samtools_output

  script:
    """
    module load python
    source activate nanocompore-env
    samtools faidx ${genome_fasta}
    """
}

process nanom6a_extract {
  publishDir "${params.resultsDir}/", mode: 'copy'
  input:
    file(genome_fasta) from extraction_genome_fasta
    file(fast5s) from extraction_resquiggle_output
    file(fast5s_list_file) from list_fast5s_output_extraction
  output:
    file("extraction_result*") into nanom6a_extract_output

  script:
    def extraction_script = "/users/PAS1405/tassosm/Work/testing-software/nanom6A_2021_10_22/extract_raw_and_feature_fast.py"
    """
    JAVA_LD_LIBRARY_PATH=""
    module load java
    module load python
    source activate nanom6A_env

    python ${extraction_script} --cpu=${task.cpus} --fl=${fast5s_list_file} -o "extraction_result" --clip=10
    """
}

process nanom6a_predict {
  publishDir "${params.resultsDir}/", mode: 'copy'
  input:
    file(fast5s_list_file) from list_fast5s_output_prediction
    file(extraction_result) from nanom6a_extract_output

    path reference_fasta, stageAs: "ref.fasta" from prediction_reference_fasta
    path genome_fasta, stageAs: "genome.fasta" from prediction_genome_fasta
    path picard_dict, stageAs: "genome.dict" from picard_output
    path samtools_index, stageAs: "genome.fasta.fai" from samtools_output
    file(isoform_file) from isoform_file
  output:
    file("prediction_results")

  script:
    def prediction_script = "/users/PAS1405/tassosm/Work/testing-software/nanom6A_2021_10_22/predict_sites.py"
    """
    JAVA_LD_LIBRARY_PATH=""
    module load java
    module load python
    source activate nanom6A_env

    ls "genome.fasta"
    ls "genome.dict"
    ls "genome.fasta.fai"

    mkdir "prediction_results"
    python ${prediction_script} --model ${params.model_path} --cpu ${task.cpus} --proba ${params.prob_threshold} -i "extraction_result" -o "prediction_results" -r ${reference_fasta} -g ${genome_fasta} -b ${isoform_file}
    """
}
