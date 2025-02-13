GENOME=file(params.genome)
GENOMEDICT=file(params.genomedict)
WGSREGION=file(params.wgsregion) 
MILLSINDEL=file(params.millsindel) //Mills_and_1000G_gold_standard.indels.hg38.vcf.gz
SHAPEITINDEL=file(params.shapeitindel) //ALL.wgs.1000G_phase3.GRCh38.ncbi_remapper.20150424.shapeit2_indels.vcf.gz
KGP=file(params.kgp) //1000G_phase1.snps.high_confidence.hg38.vcf.gz"
DBSNP=file(params.dbsnp) //dbsnp_138.hg38.vcf.gz"
GNOMAD=file(params.gnomad) //somatic-hg38-af-only-gnomad.hg38.vcf.gz
PON=file(params.pon) 
VEP_CACHEDIR=file(params.vep_cache)

//Output
outdir=file(params.output)



process pileup_paired_tonly {
    input:
        tuple val(tumorname), path(tumor), path(tumorbai), path(bed)
    
    output:
        tuple val(tumorname),
        path("${tumor.simpleName}_${bed.simpleName}.tumor.pileup.table")

    script:

    """
    gatk --java-options -Xmx48g GetPileupSummaries \
        -I ${tumor} \
        -V ${KGP} \
        -L ${bed} \
        -O ${tumor.simpleName}_${bed.simpleName}.tumor.pileup.table 

    """

    stub:
    """
    touch ${tumor.simpleName}_${bed.simpleName}.tumor.pileup.table

    """

}


process contamination_tumoronly {
    publishDir(path: "${outdir}/vcfs/mutect2/", mode: 'copy')

    input:
        tuple val(tumorname),
        path(tumor_pileups)

    output:
        tuple val(tumorname),
        path("${tumorname}_allpileups.table"),
        path("${tumorname}.contamination.table")

    script:
    //Gather all the Pileup summaries first for Tumor and Also for NORMAL and then run!
    alltumor = tumor_pileups.join(" -I ")


    """
    gatk GatherPileupSummaries \
    --sequence-dictionary ${GENOMEDICT} \
    -I ${alltumor} -O ${tumorname}_allpileups.table
    
    gatk CalculateContamination \
        -I ${tumorname}_allpileups.table \
        -O ${tumorname}.contamination.table

    """

    stub:
    """
    touch ${tumorname}_allpileups.table
    touch ${tumorname}.contamination.table
    """

}



process learnreadorientationmodel_tonly {
    publishDir(path: "${outdir}/vcfs/mutect2", mode: 'copy')

    input:
        tuple val(sample), path(f1r2)
      
    output:
    tuple val(sample), path("${sample}.read-orientation-model.tar.gz")

    script: 
    f1r2in = f1r2.join(" --input ")

    """
    gatk LearnReadOrientationModel \
        --output ${sample}.read-orientation-model.tar.gz \
        --input ${f1r2in}
    """

    stub:
    """
    touch ${sample}.read-orientation-model.tar.gz
    """
}





process mergemut2stats_tonly {
    publishDir(path: "${outdir}/vcfs/mutect2", mode: 'copy')

    input:
        tuple val(sample), path(stats)
      
    output:
        tuple val(sample), path("${sample}.final.stats")

    script: 
    statsin = stats.join(" --stats ")

    """
    gatk MergeMutectStats \
        --stats ${statsin} \
        -O ${sample}.final.stats
    """

    stub:
    """
    touch ${sample}.final.stats
    """

}



process mutect2_t_tonly {
    
    input:
        tuple val(tumorname), path(tumor), path(tumorbai), path(bed)
    
    output:
        tuple val(tumorname),
        path("${tumor.simpleName}_${bed.simpleName}.tonly.mut2.vcf.gz"),
        path("${tumor.simpleName}_${bed.simpleName}.f1r2.tar.gz"),
        path("${tumor.simpleName}_${bed.simpleName}.tonly.mut2.vcf.gz.stats")
    
    script:

    """
    gatk Mutect2 \
    --reference ${GENOME} \
    --intervals ${bed} \
    --input ${tumor} \
    --tumor-sample ${tumor.simpleName} \
    --germline-resource ${GNOMAD} \
    --panel-of-normals ${PON} \
    --output ${tumor.simpleName}_${bed.simpleName}.tonly.mut2.vcf.gz \
    --f1r2-tar-gz ${tumor.simpleName}_${bed.simpleName}.f1r2.tar.gz \
    --independent-mates    
    """

    stub:
    """
    touch ${tumor.simpleName}_${bed.simpleName}.tonly.mut2.vcf.gz
    touch ${tumor.simpleName}_${bed.simpleName}.f1r2.tar.gz
    touch ${tumor.simpleName}_${bed.simpleName}.tonly.mut2.vcf.gz.stats
    """


}



process mutect2filter_tonly {
    publishDir(path: "${outdir}/vcfs/mutect2_tonly", mode: 'copy')

    input:
        tuple val(sample), path(mutvcfs), path(stats), path(obs), path(pileups),path(tumorcontamination)
    output:
        tuple val(sample), path("${sample}.tonly.mut2.marked.vcf.gz"), 
        path("${sample}.tonly.mut2.norm.vcf.gz"), path("${sample}.tonly.marked.vcf.gz.filteringStats.tsv")

    script:
    //Include the stats and  concat ${mutvcfs} -Oz -o ${sample}.concat.vcf.gz
    mut2in = mutvcfs.join(" -I ")


    """
    gatk GatherVcfs -I ${mut2in} -O ${sample}.tonly.concat.vcf.gz 
    gatk IndexFeatureFile -I ${sample}.tonly.concat.vcf.gz 
    gatk FilterMutectCalls \
        -R ${GENOME} \
        -V ${sample}.tonly.concat.vcf.gz \
        --ob-priors ${obs} \
        --contamination-table ${tumorcontamination} \
        --stats ${stats} \
        -O ${sample}.tonly.mut2.marked.vcf.gz

    gatk SelectVariants \
        -R ${GENOME} \
        --variant ${sample}.tonly.marked.vcf.gz \
        --exclude-filtered \
        --output ${sample}.tonly.mut2.final.vcf.gz

    bcftools sort ${sample}.tonly.mut2.final.vcf.gz -@ 16 -Oz |\
    bcftools norm --threads 16 --check-ref s -f $GENOME -O v |\
        awk '{{gsub(/\\y[W|K|Y|R|S|M]\\y/,"N",\$4); OFS = "\t"; print}}' |\
        sed '/^\$/d' > ${sample}.tonly.mut2.norm.vcf.gz

    """

    stub:
    """
    touch ${sample}.tonly.mut2.marked.vcf.gz
    touch ${sample}.tonly.mut2.norm.vcf.gz
    touch ${sample}.tonly.marked.vcf.gz.filteringStats.tsv
    """
}






process varscan_tonly {
    input:
        tuple val(tumorname), path(tumor), path(tumorbai), 
        path(bed),
        path(tumorpileup),  path(tumor_con_table)
    
    output:
        tuple val(tumorname),
        path("${tumor.simpleName}_${bed.simpleName}.tonly.varscan.vcf")
    
    shell:

    """
    varscan_opts="--strand-filter 0 --min-var-freq 0.01 --output-vcf 1 --variants 1"
    pileup_cmd="samtools mpileup -d 100000 -q 15 -Q 15 -f !GENOME !{tumor}"
    varscan_cmd="varscan mpileup2cns <($pileup_cmd) $varscan_opts"


    eval "$varscan_cmd > {output.vcf}.gz"
    eval "bcftools view -U {output.vcf}.gz > {output.vcf}"
    """

    stub:
    
    """
    touch ${tumor.simpleName}_${bed.simpleName}.tonly.varscan.vcf
    
    """

}

process vardict_tonly {
    
    input:
        tuple val(tumorname), path(tumor), path(tumorbai), path(bed)
    
    output:
        tuple val(tumorname),
        path("${tumor.simpleName}_${bed.simpleName}.tonly.vardict.vcf")
    
    script:

    """
    VarDict -G $GENOME \
        -f 0.05 \
        -x 500 \
        --nosv \
        -b ${tumor} \
        -t -Q 20 -c 1 -S 2 -E 3 \
        -R ${bed} \
        | teststrandbias.R \
        | var2vcf_valid.pl \
            -N ${tumor} \
            -Q 20 \
            -d 10 \
            -v 6 \
            -S \
            -E \
            -f 0.05 >  ${tumor.simpleName}_${bed.simpleName}.tonly.vardict.vcf

    """

    stub:
    
    """
    touch ${tumor.simpleName}_${bed.simpleName}.tonly.vardict.vcf

    """


}


process annotvep_tonly {
    publishDir("${outdir}/mafs", mode: "copy")

    input:
        tuple val(tumorsample), 
        val(vc), path(tumorvcf) 


    output:
        path("tumor_only/${vc}/${tumorsample}.tonly.maf")

    shell:

    """
    
    zcat !{tumorvcf}.vcf.gz > !{tumorvcf}.vcf

    vcf2maf.pl \
    --vep-forks 16 --input-vcf !{tumorvcf}.vcf \
    --output-maf !{vc}/!{tumorsample}.tonly.maf \
    --tumor-id !{tumorsample} \
    --vep-path /opt/vep/src/ensembl-vep \
    --vep-data $VEP_CACHEDIR \
    --ncbi-build GRCh38 --species homo_sapiens --ref-fasta !{GENOME}

    """

    stub:
    """
    mkdir -p tumor_only/${vc}
    touch tumor_only/${vc}/${tumorsample}.tonly.maf
    """
}

process combinemafs_tonly {
    publishDir(path: "${outdir}/mafs/tumor_only", mode: 'copy')

    input: 
        path(allmafs)

    output:
        path("final_tonly.maf")

    shell:
    mafin= allmafs.join(" ")
    
    """
    echo "Combining MAFs..."
    head -2 ${allmafs[0]} > final_tonly.maf
    awk 'FNR>2 {{print}}' ${mafin}  >> final_tonly.maf
    """

    stub:
    """
    touch final_tonly.maf
    """
}



