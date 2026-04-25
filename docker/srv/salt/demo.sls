demo_file:
  file.managed:
    - name: /tmp/salt-demo.txt
    - contents: |
        Salt is working!
        Managed by Salt master from Docker.
