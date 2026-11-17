def pipelineFromSCM = { String jobName, String pipelinePath, String pollSpec, boolean isDisabled ->
  pipelineJob(jobName) {
    description("Managed by slidebolt-ci/controller/jobs.groovy")
    disabled(isDisabled)
    if (pollSpec) {
      triggers { scm(pollSpec) }
    }
    logRotator { numToKeep(20); artifactNumToKeep(10) }
    definition {
      cpsScm {
        scm {
          git {
            remote { url('https://github.com/slidebolt/slidebolt-ci.git') }
            branch('*/main')
          }
        }
        scriptPath(pipelinePath)
        lightweight(true)
      }
    }
  }
}

pipelineFromSCM('slidebolt-bootstrap-verify', 'pipelines/Jenkinsfile.slidebolt', '', false)
pipelineFromSCM('slidebolt-candidate', 'pipelines/Jenkinsfile.slidebolt-candidate', 'H/5 * * * *', false)
pipelineFromSCM('slidebolt-promote', 'pipelines/Jenkinsfile.slidebolt-promote', '', false)
pipelineFromSCM('android-verify', 'pipelines/Jenkinsfile.android', 'H/5 * * * *', false)
pipelineFromSCM('android-promote', 'pipelines/Jenkinsfile.android-promote', '', true)

