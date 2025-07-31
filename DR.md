# Distaster Recovery Procedure

Make a shell script for disaster recovery. Document its usage in a DR-README.md file.

These are the steps that need to be followed:

- Test for existence of the `cmk` binary. If not:
  - Download the binary from <https://github.com/apache/cloudstack-cloudmonkey/releases>
  - Schematically:
  
    ```bash
      sudo wget <file link> -O /usr/local/bin/cmk
      sudo chmod +x /usr/local/bin/cmk
    ```

