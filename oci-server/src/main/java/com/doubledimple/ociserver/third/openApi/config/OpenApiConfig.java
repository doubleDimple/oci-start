package com.doubledimple.ociserver.third.openApi.config;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import io.swagger.v3.oas.annotations.info.Contact;
import io.swagger.v3.oas.annotations.info.Info;
import io.swagger.v3.oas.annotations.info.License;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import org.springdoc.core.GroupedOpenApi;
import org.springdoc.core.customizers.OpenApiCustomiser;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@OpenAPIDefinition(
        info = @Info(
                title = "OCI-START API",
                version = "1.0.0",
                description = "OCI-START API文档",
                contact = @Contact(
                        name = "doubleDimple",
                        email = "dev@example.com"
                )
                /*license = @License(
                        name = "MIT",
                        url = "https://opensource.org/licenses/MIT"
                )*/
        ),
        security = { @SecurityRequirement(name = "bearerAuth") }
)
@SecurityScheme(
        name = "bearerAuth",
        type = SecuritySchemeType.HTTP,
        scheme = "bearer",
        bearerFormat = "JWT"
)
public class OpenApiConfig {

    @Bean
    public GroupedOpenApi openApiGroup() {
        return GroupedOpenApi.builder()
                .group("open-api")
                .displayName("Open API")
                .pathsToMatch("/oci-start/open-api/**")
                .build();
    }
}
