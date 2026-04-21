def call(String title, String description, int color) {
    withCredentials([string(credentialsId: 'jenkins-discord-webhook', variable: 'DISCORD_WEBHOOK_URL')]) {
        
        def cleanDesc = description.replace('\n', '\\n').replace('"', '\\"')
        def payload = """{
            "embeds": [{
                "title": "${title}",
                "description": "${cleanDesc}",
                "color": ${color}
            }]
        }"""
        
        writeFile file: 'discord_payload.json', text: payload
        
        sh "curl -s --max-time 10 -H 'Content-Type: application/json' -X POST -d @discord_payload.json ${DISCORD_WEBHOOK_URL} || true"
    }
}