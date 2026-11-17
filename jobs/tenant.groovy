import groovy.json.JsonSlurper

def catalog = new JsonSlurper().parseText(readFileFromWorkspace('catalog/packages.json'))
if (catalog.schemaVersion != 1 || !(catalog.packages instanceof List)) {
  throw new IllegalArgumentException('catalog/packages.json is not schema version 1')
}

folder('Slidebolt') {
  description('Slidebolt tenant; jobs, credentials, agents, and artifacts are isolated from other Jenkins tenants.')
}
folder('Slidebolt/packages') {
  description('Commit-level package verification generated from slidebolt-ci/catalog/packages.json.')
}
folder('Slidebolt/release') {
  description('Complete product candidate and promotion gates.')
}

catalog.packages.each { item ->
  if (!(item.repository ==~ /[a-z0-9][a-z0-9-]*/) || !(item.kind in ['go', 'node', 'zigbee-host', 'ui', 'android'])) {
    throw new IllegalArgumentException("invalid package catalog entry: ${item}")
  }
  pipelineJob("Slidebolt/packages/${item.repository}") {
    description("Verifies the exact ${item.repository} commit and archives an immutable package proof.")
    logRotator { numToKeep(20); artifactNumToKeep(10) }
    parameters {
      stringParam('REPOSITORY', item.repository, 'Catalog-owned repository; do not change for scheduled builds')
      choiceParam('PACKAGE_KIND', [item.kind], 'Catalog-owned verification contract')
      stringParam('REVISION', '*/main', 'Git branch, tag, or commit to prove')
    }
    triggers { scm('H/5 * * * *') }
    definition {
      cpsScm {
        scm {
          git {
            remote {
              url('https://github.com/slidebolt/slidebolt-ci.git')
            }
            branch('*/main')
          }
        }
        scriptPath('pipelines/Jenkinsfile.package')
        lightweight(true)
      }
    }
  }
}

pipelineJob('Slidebolt/release/candidate') {
  description('Builds and verifies the complete image from release/main without publishing it.')
  logRotator { numToKeep(20); artifactNumToKeep(10) }
  triggers { scm('H/5 * * * *') }
  definition {
    cpsScm {
      scm {
        git {
          remote { url('https://github.com/slidebolt/slidebolt-ci.git') }
          branch('*/main')
        }
      }
      scriptPath('pipelines/Jenkinsfile.slidebolt-candidate')
      lightweight(true)
    }
  }
}

pipelineJob('Slidebolt/release/promote') {
  description('Publishes an exact successful candidate as an immutable Slidebolt release.')
  logRotator { numToKeep(20); artifactNumToKeep(10) }
  definition {
    cpsScm {
      scm {
        git {
          remote { url('https://github.com/slidebolt/slidebolt-ci.git') }
          branch('*/main')
        }
      }
      scriptPath('pipelines/Jenkinsfile.slidebolt-promote')
      lightweight(true)
    }
  }
}
