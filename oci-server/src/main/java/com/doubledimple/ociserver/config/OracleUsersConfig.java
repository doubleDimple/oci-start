package com.doubledimple.ociserver.config;

import com.doubledimple.ociserver.domain.User;
import lombok.Data;
import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;

/**
 * @author doubleDimple
 * @date 2024:09:22日 11:31
 */
//@Component
@Configuration
@ConfigurationProperties(prefix = "oracle")
public class OracleUsersConfig {

    private Map<String, User> users = new HashMap<>();

    public Map<String, User> getUsers() {
        return users;
    }

    public void setUsers(Map<String, User> users) {
        this.users = users;
    }
}
