package com.doubledimple.ociserver.constant;

import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

/**
 * @author doubleDimple
 * @date 2024:09:22日 21:12
 */
public class SystemScriptShell {


    public static String getShell(String passwd){
        return "#cloud-config\n" +
                "ssh_pwauth: yes\n" +
                "chpasswd:\n" +
                "  list: |\n" +
                "    root:" + passwd + "\n" +
                "  expire: false\n" +
                "write_files:\n" +
                "  - path: /tmp/setup_root_access.sh\n" +
                "    permissions: '0700'\n" +
                "    content: |\n" +
                "      #!/bin/bash\n" +
                "      \n" +
                "      # Detect OS\n" +
                "      if [ -f /etc/os-release ]; then\n" +
                "        . /etc/os-release\n" +
                "        OS=$ID\n" +
                "      else\n" +
                "        echo \"Cannot detect OS, exiting.\"\n" +
                "        exit 1\n" +
                "      fi\n" +
                "      \n" +
                "      # Convert to lowercase\n" +
                "      OS=$(echo \"$OS\" | tr '[:upper:]' '[:lower:]')\n" +
                "      \n" +
                "      # Configure SSH\n" +
                "      sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\n" +
                "      sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\n" +
                "      \n" +
                "      # Restart SSH service\n" +
                "      if command -v systemctl >/dev/null 2>&1; then\n" +
                "        systemctl restart sshd\n" +
                "      else\n" +
                "        service sshd restart\n" +
                "      fi\n" +
                "      \n" +
                "      # Set up warning message\n" +
                "      echo \"WARNING: Please change the root password immediately after login!\" | tee /etc/motd\n" +
                "      \n" +
                "      # OS-specific configurations\n" +
                "      case $OS in\n" +
                "        ubuntu|debian)\n" +
                "          # Ubuntu/Debian specific commands\n" +
                "          sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\n" +
                "          ;;\n" +
                "        ol|rhel|centos|almalinux|rocky)\n" +
                "          # Oracle Linux/RHEL/CentOS/AlmaLinux/Rocky Linux specific commands\n" +
                "          sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\n" +
                "          ;;\n" +
                "        *)\n" +
                "          echo \"Unsupported OS: $OS\" >&2\n" +
                "          ;;\n" +
                "      esac\n" +
                "      \n" +
                "      # Additional security measures\n" +
                "      chage -d 0 root  # Force password change on next login\n" +
                "runcmd:\n" +
                "  - bash /tmp/setup_root_access.sh\n" +
                "  - rm /tmp/setup_root_access.sh\n";
    }
}
