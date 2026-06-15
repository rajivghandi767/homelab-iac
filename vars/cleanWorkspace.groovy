def call() {
    echo "🧹 Sweeping workspace to save disk space..."
    cleanWs(
        cleanWhenAborted: true,
        cleanWhenFailure: true,
        cleanWhenNotBuilt: true,
        cleanWhenSuccess: true,
        cleanWhenUnstable: true,
        deleteDirs: true
    )
}
