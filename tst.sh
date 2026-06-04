for pid in 69919 48863 819 687 675 35027 47700 47709 47716 47761; do
    echo "testing pid $pid"

    capturer source process-audio \
        --pid "$pid" \
        --duration 3 \
        --output "/tmp/facetime-process-$pid.wav" \
        --overwrite || true
done
