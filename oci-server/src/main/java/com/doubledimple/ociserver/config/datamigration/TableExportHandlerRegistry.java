package com.doubledimple.ociserver.config.datamigration;

import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 所有 TableExportHandler 的注册中心
 */
@Component
public class TableExportHandlerRegistry {

    private final Map<String, TableExportHandler> registry = new HashMap<>();

    public TableExportHandlerRegistry(List<TableExportHandler> handlers) {
        if (handlers != null) {
            for (TableExportHandler handler : handlers) {
                registry.put(handler.getTableName().toUpperCase(), handler);
            }
        }
    }

    public TableExportHandler getHandler(String tableName) {
        if (tableName == null) return null;
        return registry.get(tableName.toUpperCase());
    }
}
