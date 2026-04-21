@Library('homelab-library') _

pipeline {
    agent any

    options {
        disableConcurrentBuilds()
    }

    environment {
        APP_NAME = "RW Homelab Vault"
    }

    stages {
        stage('🔓 Unseal Vault') {
            steps {
                script {
                    unsealVault()
                }
            }
        }
    }

    post {
        success {
            script {
                def timestamp = sh(returnStdout: true, script: "TZ='America/New_York' date +'%a, %d %b %Y at %H:%M %Z'").trim()
                def msg = ":unlock: **${env.APP_NAME} Unsealed**\nThe unseal job completed successfully.\n\n:clock4: **Time:** ${timestamp}"
                
                notifyDiscord("✅ Vault Status: UNSEALED", msg, 3066993)
            }
        }
        failure {
            script {
                def failTime = sh(returnStdout: true, script: "TZ='America/New_York' date +'%a, %d %b %Y at %H:%M %Z'").trim()
                def msg = ":x: **${env.APP_NAME} Unseal Failed**\n**:warning: Error Details:**\nCheck Jenkins logs for build #${BUILD_NUMBER}. The Vault may still be locked.\n\n:clock4: **Time:** ${failTime}"
                
                notifyDiscord("🚨 Vault Alert", msg, 15158332)
            }
        }
    }
}