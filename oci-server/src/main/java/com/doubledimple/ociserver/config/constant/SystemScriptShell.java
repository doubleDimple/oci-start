package com.doubledimple.ociserver.config.constant;

import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;

/**
 * @author doubleDimple
 * @date 2024:09:22日 21:12
 */
public class SystemScriptShell {

    public static final String vcnName = "oci-start-pro-vcn";

    public static final String internetGatewayName = "oci-start-pro-internet-gateway";

    public static final String subnetName = "oci-start-pro-subnet";

    public static final String bootVolumeName = "oci-start-pro-boot-volume";

    public static final String networkSecurityGroupName = "oci-start-pro-nsg";


    /**
    * @Description: 添加欢迎语
    * @Param: [java.lang.String]
    * @return: java.lang.String
    * @Author: doubleDimple
    * @Date: 12/21/24 9:55 AM
    */
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
                "      # Ensure PrintMotd is set to yes\n" +
                "      if grep -q \"^#\\?PrintMotd\" /etc/ssh/sshd_config; then\n" +
                "        sed -i 's/^#\\?PrintMotd.*/PrintMotd yes/' /etc/ssh/sshd_config\n" +
                "      else\n" +
                "        echo \"PrintMotd yes\" >> /etc/ssh/sshd_config\n" +
                "      fi\n" +
                "      # Ensure PrintLastLog is set to yes\n" +
                "      if grep -q \"^#\\?PrintLastLog\" /etc/ssh/sshd_config; then\n" +
                "        sed -i 's/^#\\?PrintLastLog.*/PrintLastLog yes/' /etc/ssh/sshd_config\n" +
                "      else\n" +
                "        echo \"PrintLastLog yes\" >> /etc/ssh/sshd_config\n" +
                "      fi\n\n" +
                "      # Restart SSH service\n" +
                "      if command -v systemctl >/dev/null 2>&1; then\n" +
                "        systemctl restart sshd\n" +
                "      else\n" +
                "        service sshd restart\n" +
                "      fi\n" +
                "      \n" +
                "      # Set up welcome message\n" +
                "      {\n" +
                "        echo \"\"\n" +
                "        echo \"Welcome to OCI-START\"\n" +
                "        echo \"\"\n" +
                "        echo \"Source code address: https://github.com/doubleDimple/oci-start\"\n" +
                "      } | tee /etc/motd\n" +
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
                "runcmd:\n" +
                "  - bash /tmp/setup_root_access.sh\n" +
                "  - rm /tmp/setup_root_access.sh\n";
    }


    /**
     * 创建启用root密码登录的启动脚本 (使用 startup-script 而不是 user-data)
     *
     * @param rootPassword root用户密码
     * @return 启动脚本
     */
    public static String getStartupScript(String rootPassword) {
        return "#!/bin/bash\n" +
                "set -e\n" +
                "exec > >(tee /var/log/startup-script.log) 2>&1\n" +
                "\n" +
                "echo \"[$(date)] Starting root access setup...\"\n" +
                "\n" +
                "# 设置root密码\n" +
                "echo \"root:" + rootPassword + "\" | chpasswd\n" +
                "echo \"[$(date)] Root password updated\"\n" +
                "\n" +
                "# 备份原始SSH配置\n" +
                "cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d-%H%M%S)\n" +
                "\n" +
                "# 确保SSH配置目录存在\n" +
                "mkdir -p /etc/ssh/sshd_config.d\n" +
                "\n" +
                "# 创建专门的配置文件启用root密码登录\n" +
                "cat > /etc/ssh/sshd_config.d/99-enable-root-password.conf << 'EOF'\n" +
                "# Enable root password authentication\n" +
                "PermitRootLogin yes\n" +
                "PasswordAuthentication yes\n" +
                "ChallengeResponseAuthentication no\n" +
                "UsePAM yes\n" +
                "EOF\n" +
                "\n" +
                "# 同时修改主配置文件（双重保险）\n" +
                "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\n" +
                "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\n" +
                "sed -i 's/^#\\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config\n" +
                "sed -i 's/^#\\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config\n" +
                "\n" +
                "# 如果配置不存在则添加\n" +
                "grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config\n" +
                "grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config\n" +
                "\n" +
                "# 测试SSH配置\n" +
                "if sshd -t; then\n" +
                "    echo \"[$(date)] SSH configuration test passed\"\n" +
                "else\n" +
                "    echo \"[$(date)] SSH configuration test failed, restoring backup\"\n" +
                "    cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config 2>/dev/null || true\n" +
                "    exit 1\n" +
                "fi\n" +
                "\n" +
                "# 重启SSH服务\n" +
                "systemctl restart ssh || systemctl restart sshd\n" +
                "echo \"[$(date)] SSH service restarted\"\n" +
                "\n" +
                "# 验证SSH服务状态\n" +
                "if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then\n" +
                "    echo \"[$(date)] SSH service is running\"\n" +
                "else\n" +
                "    echo \"[$(date)] SSH service is not running, attempting to start\"\n" +
                "    systemctl start ssh || systemctl start sshd\n" +
                "fi\n" +
                "\n" +
                "# 创建欢迎消息\n" +
                "cat > /etc/motd << 'EOF'\n" +
                "\n" +
                "Welcome to OCI-START\n" +
                "\n" +
                "Source code address: https://github.com/doubleDimple/oci-start\n" +
                "\n" +
                "EOF\n" +
                "\n" +
                "# 创建完成标记\n" +
                "echo \"[$(date)] Root access setup completed successfully\" > /root/.root-access-setup-complete\n" +
                "\n" +
                "# 显示最终配置状态\n" +
                "echo \"[$(date)] Final SSH configuration:\"\n" +
                "sshd -T | grep -E \"(passwordauthentication|permitrootlogin)\"\n" +
                "\n" +
                "echo \"[$(date)] Setup complete. Root login with password should now be enabled.\"\n";
    }
}
