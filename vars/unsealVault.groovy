def call(String vaultAddr = 'http://vault:8200') {
    echo "Checking Vault Seal Status at ${vaultAddr}..."
    def statusJson = sh(script: "curl -s ${vaultAddr}/v1/sys/seal-status", returnStdout: true).trim()
    
    if (statusJson.contains('"sealed":false')) {
        echo "✅ Vault is ALREADY UNSEALED. No action required."
        return
    }

    echo "🔒 Vault is SEALED. Initiating unseal sequence..."
    withCredentials([
        string(credentialsId: 'VAULT_UNSEAL_KEY_1', variable: 'KEY1'),
        string(credentialsId: 'VAULT_UNSEAL_KEY_2', variable: 'KEY2'),
        string(credentialsId: 'VAULT_UNSEAL_KEY_3', variable: 'KEY3'),
        string(credentialsId: 'VAULT_UNSEAL_KEY_4', variable: 'KEY4'),
        string(credentialsId: 'VAULT_UNSEAL_KEY_5', variable: 'KEY5')
    ]) {
        for (int i = 1; i <= 5; i++) {
            echo "🚀 Injecting Key #${i}..."
            
            def currentKeyVar = "KEY${i}"
            
            sh "echo '{\"key\": \"'\$${currentKeyVar}'\"}' > vault_payload.json"
            
            // Send the payload via curl
            def output = sh(script: "curl -s -X POST -H 'Content-Type: application/json' -d @vault_payload.json ${vaultAddr}/v1/sys/unseal", returnStdout: true).trim()
            
            sh "rm vault_payload.json"
            
            if (output.contains('"sealed":false')) {
                echo "🎉 SUCCESS: Vault has been UNSEALED!"
                return 
            } else {
                echo "⚠️ Key accepted. Still sealed. Waiting for next key..."
            }
        }
        
        error("⛔ All 5 keys were tried, but Vault is still sealed. Please check Jenkins credentials.")
    }
}