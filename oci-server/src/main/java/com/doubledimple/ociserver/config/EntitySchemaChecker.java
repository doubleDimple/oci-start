package com.doubledimple.ociserver.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.ApplicationContext;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.core.io.support.ResourcePatternResolver;
import org.springframework.core.type.classreading.CachingMetadataReaderFactory;
import org.springframework.core.type.classreading.MetadataReader;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import javax.persistence.Entity;
import javax.persistence.Table;
import java.lang.reflect.Field;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * @version 1.0.0
 * @ClassName EntitySchemaChecker
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-02-19 08:59
 */
@Slf4j
@Component
public class EntitySchemaChecker implements CommandLineRunner {

    private final JdbcTemplate jdbcTemplate;
    private final ApplicationContext applicationContext;

    public EntitySchemaChecker(JdbcTemplate jdbcTemplate, ApplicationContext applicationContext) {
        this.jdbcTemplate = jdbcTemplate;
        this.applicationContext = applicationContext;
    }

    @Override
    public void run(String... args) {
        try {
            Set<Class<?>> entityClasses = scanEntityClasses("com.doubledimple.dao.entity");
            for (Class<?> entityClass : entityClasses) {
                checkAndUpdateEntitySchema(entityClass);
            }
        } catch (Exception e) {
            log.error("扫描实体类时出错: ", e);
        }
    }

    private Set<Class<?>> scanEntityClasses(String basePackage) throws Exception {
        Set<Class<?>> entityClasses = new HashSet<>();
        ResourcePatternResolver resourcePatternResolver = new PathMatchingResourcePatternResolver();
        CachingMetadataReaderFactory metadataReaderFactory = new CachingMetadataReaderFactory(resourcePatternResolver);

        String pattern = ResourcePatternResolver.CLASSPATH_ALL_URL_PREFIX +
                basePackage.replace('.', '/') + "/**/*.class";
        Resource[] resources = resourcePatternResolver.getResources(pattern);

        for (Resource resource : resources) {
            MetadataReader metadataReader = metadataReaderFactory.getMetadataReader(resource);
            String className = metadataReader.getClassMetadata().getClassName();
            Class<?> clazz = Class.forName(className);

            if (clazz.isAnnotationPresent(Entity.class)) {
                entityClasses.add(clazz);
            }
        }
        return entityClasses;
    }

    private void checkAndUpdateEntitySchema(Class<?> entityClass) {
        String tableName = getTableName(entityClass);

        Field[] fields = entityClass.getDeclaredFields();
        for (Field field : fields) {
            // 跳过静态字段和带有@Transient注解的字段
            if (java.lang.reflect.Modifier.isStatic(field.getModifiers()) ||
                    field.isAnnotationPresent(javax.persistence.Transient.class)) {
                continue;
            }

            String columnName = getColumnName(field);
            if (!isColumnExists(tableName, columnName)) {
                String columnDefinition = generateColumnDefinition(field);
                try {
                    String sql = String.format("ALTER TABLE %s ADD COLUMN %s %s",
                            tableName, columnName, columnDefinition);
                    log.debug("执行SQL: {}", sql);
                    jdbcTemplate.execute(sql);
                    log.debug("成功添加列 {}.{}", tableName, columnName);
                } catch (Exception e) {
                    log.error("添加列 {}.{} 时出错: ", tableName, columnName, e);
                }
            }
        }
    }

    private String getTableName(Class<?> entityClass) {
        Table tableAnn = entityClass.getAnnotation(Table.class);
        if (tableAnn != null && !tableAnn.name().isEmpty()) {
            return tableAnn.name().toUpperCase();
        }
        return entityClass.getSimpleName().toUpperCase();
    }

    private String getColumnName(Field field) {
        javax.persistence.Column columnAnn = field.getAnnotation(javax.persistence.Column.class);
        if (columnAnn != null && !columnAnn.name().isEmpty()) {
            return columnAnn.name().toUpperCase();
        }
        // 驼峰转下划线
        return camelToSnake(field.getName()).toUpperCase();
    }

    private String generateColumnDefinition(Field field) {
        Class<?> type = field.getType();
        if (type == String.class) {
            return "VARCHAR(255)";
        } else if (type == Long.class || type == long.class) {
            return "BIGINT DEFAULT 0";
        } else if (type == Integer.class || type == int.class) {
            return "INTEGER DEFAULT 0";
        } else if (type == Boolean.class || type == boolean.class) {
            return "BOOLEAN DEFAULT FALSE";
        } else if (type == java.time.LocalDateTime.class) {
            return "TIMESTAMP";
        } else if (type == java.sql.Timestamp.class) {
            return "TIMESTAMP";
        }
        // 可以根据需要添加更多类型的映射
        return "VARCHAR(255)";
    }

    private boolean isColumnExists(String tableName, String columnName) {
        try {
            String sql = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS " +
                    "WHERE TABLE_NAME = ? AND COLUMN_NAME = ?";
            List<String> columns = jdbcTemplate.query(sql,
                    (rs, rowNum) -> rs.getString("COLUMN_NAME"),
                    tableName, columnName);
            return !columns.isEmpty();
        } catch (Exception e) {
            log.error("检查列{}是否存在时出错: ", columnName, e);
            return false;
        }
    }

    private String camelToSnake(String str) {
        return str.replaceAll("([a-z])([A-Z])", "$1_$2").toLowerCase();
    }
}
