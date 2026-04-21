def call(String title, String description, int color) {
    withCredentials([string(credentialsId: 'jenkins-discord-webhook', variable: 'DISCORD_WEBHOOK_URL_JENKINS')]) {
        
        def cleanDesc = description.replace('\n', '\\n').replace('"', '\\"')
        
        def payload = """{
            "embeds": [{
                "title": "${title}",
                "description": "${cleanDesc}",
                "color": ${color}
            }]
        }"""
        
        writeFile file: 'discord_payload.json', text: payload
        
        // FIX: The sh step is now wrapped in single quotes ('...'). 
        // We use double quotes inside the shell command for the headers and URL.
        sh 'curl -s --max-time 10 -H "Content-Type: application/json" -X POST -d @discord_payload.json "$DISCORD_WEBHOOK_URL_JENKINS" || true'
        
        // Clean up the payload file so it doesn't linger in the workspace
        sh 'rm discord_payload.json'
    }
}