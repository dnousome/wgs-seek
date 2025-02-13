#!/usr/bin/env nextflow
nextflow.enable.dsl=2

GENOME=file(params.genome)
GERMLINEHET="/data/SCLC-BRAINMETS/cn/copy_number/GermlineHetPon.38.vcf.gz"
GCPROFILE='/data/SCLC-BRAINMETS/cn/copy_number/GC_profile.1000bp.38.cnp'
DIPLODREG='/data/SCLC-BRAINMETS/cn/copy_number/DiploidRegions.38.bed.gz'
ENSEMBLCACHE='/data/SCLC-BRAINMETS/cn/common/ensembl_data'
DRIVERS='/data/SCLC-BRAINMETS/cn/common/DriverGenePanel.38.tsv'
HOTSPOTS='/data/SCLC-BRAINMETS/cn/variants/KnownHotspots.somatic.38.vcf.gz'
cobalt="/data/SCLC-BRAINMETS/cn/cobalt_v1.14.jar"
amber="/data/SCLC-BRAINMETS/cn/amber-3.9.jar"
purple="/data/SCLC-BRAINMETS/cn/purple_v3.8.2.jar"


date = new Date().format( 'yyyyMMdd' )

outdir=file(params.output)


log.info """\
         W G S S E E K   P I P E L I N E    
         =============================
         Samples:  ${params.sample_sheet}
         """
         .stripIndent()

//Purple 
process amber {
    module=["java/12.0.1","R/3.6.3"]
    publishDir("${outdir}/amber", mode: 'copy')
    input:
        tuple val(samplename), path("${samplename}.bqsr.bam"), path("${samplename}.bqsr.bam.bai")

    output:
        tuple val(samplename), path("${samplename}_amber")
        //path("${samplename}.amber.baf.tsv.gz"),
        //path("${samplename}.amber.baf.pcf"),
        //path("${samplename}.amber.qc")
        //path("${samplename}.amber.contamination.vcf.gz") Contamination maybe only with tumor

    script:

    """

    java -Xmx32G -cp $amber com.hartwig.hmftools.amber.AmberApplication \
    -tumor ${samplename} -tumor_bam ${samplename}.bqsr.bam \
    -output_dir ${samplename}_amber \
    -threads 16 \
    -ref_genome_version V38 \
    -loci $GERMLINEHET

    """

    stub:

    """
    mkdir ${samplename}_amber
    touch ${samplename}_amber/${samplename}.amber.baf.tsv.gz ${samplename}_amber/${samplename}.amber.baf.pcf ${samplename}_amber/${samplename}.amber.qc 
    """
}

process cobalt {
    module=["java/12.0.1","R/3.6.3"]
    publishDir("${outdir}/cobalt", mode: 'copy')

    input:
        tuple val(samplename), path("${samplename}.bqsr.bam"), path("${samplename}.bqsr.bam.bai")

    output:
        tuple val(samplename), path("${samplename}_cobalt")
        //path("${samplename}/${samplename}.cobalt.ratio.tsv.gz"), 
        //path("${samplename}/${samplename}.cobalt.ratio.pcf"),
        //path("${samplename}/${samplename}.cobalt.gc.median.tsv")

    script:

    """

    java -jar -Xmx8G $cobalt \
    -tumor ${samplename} -tumor_bam ${samplename}.bqsr.bam \
    -output_dir ${samplename}_cobalt \
    -threads 16 \
    -tumor_only_diploid_bed $DIPLODREG \
    -gc_profile /data/SCLC-BRAINMETS/cn/copy_number/GC_profile.1000bp.38.cnp 

    """

    stub:

    """
    mkdir ${samplename}_cobalt
    touch ${samplename}_cobalt/${samplename}.cobalt.ratio.tsv.gz ${samplename}_cobalt/${samplename}.cobalt.ratio.pcf ${samplename}_cobalt/${samplename}.cobalt.gc.median.tsv
    """
}

process purple {
    module=["java/12.0.1","R/3.6.3"]

    publishDir("${outdir}/purple", mode: 'copy')

    input:
        tuple val(samplename), path(cobaltin), path(amberin), path("${samplename}.tonly.final.mut2.vcf.gz")

    output:
        tuple val(samplename), path("${samplename}")

    script:

    """

    java -jar $purple \
    -tumor ${samplename} \
    -amber ${amberin} \
    -cobalt ${cobaltin} \
    -gc_profile $GCPROFILE \
    -ref_genome_version 38 \
    -ref_genome $GENOME \
    -ensembl_data_dir $ENSEMBLCACHE \
    -somatic_vcf ${samplename}.tonly.final.mut2.vcf.gz \
    -driver_gene_panel $DRIVERS \
    -somatic_hotspots $HOTSPOTS \
    -output_dir ${samplename}

    """

    stub:

    """
    mkdir ${samplename}
    touch ${samplename}/${samplename}.purple.cnv.somatic.tsv ${samplename}/${samplename}.purple.cnv.gene.tsv ${samplename}/${samplename}.driver.catalog.somatic.tsv
    """

}


//Workflow
workflow {
    sample_sheet=Channel.fromPath(params.sample_sheet, checkIfExists: true).view()
                       .ifEmpty { "sample sheet not found" }
                       .splitCsv(header:true, sep: "\t", strip:true)
                       .map { row -> tuple(
                        row.ID,
                        row.bam,
                        row.vcf
                       )
                                  }


    baminput=sample_sheet
           .map{samplename,bam,vcf-> tuple(samplename,file(bam),file("${bam}.bai"))}

    somaticinput=sample_sheet
           .map{samplename,bam,vcf-> tuple(samplename,file(vcf))}

    cobalt(baminput)
    amber(baminput) 

    pre1=cobalt.out.join(amber.out)
    pre1.join(somaticinput).view()| purple
}
    


