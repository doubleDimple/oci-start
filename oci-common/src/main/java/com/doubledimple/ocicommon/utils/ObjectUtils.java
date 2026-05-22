package com.doubledimple.ocicommon.utils;

import java.lang.reflect.Method;
import java.util.Map;

/**
 * @version 1.0.0
 * @ClassName ObjectUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-10 14:59
 */
public class ObjectUtils {

    public static <T> T mapToObject(Map<String, String> map, Class<T> clazz) throws Exception {
        T obj = clazz.getDeclaredConstructor().newInstance();

        for (Map.Entry<String, String> entry : map.entrySet()) {
            String key = entry.getKey();
            Object value = entry.getValue();

            try {
                // 获取属性名对应的setter方法
                String setterName = "set" + key.substring(0, 1).toUpperCase() + key.substring(1);

                // 查找对应的setter方法
                Method setter = null;
                for (Method method : clazz.getMethods()) {
                    if (method.getName().equals(setterName) && method.getParameterCount() == 1) {
                        setter = method;
                        break;
                    }
                }

                if (setter != null) {
                    // 调用setter方法设置属性值
                    setter.invoke(obj, value);
                }
            } catch (Exception e) {
                // 处理找不到对应属性或方法的情况
                System.err.println("无法设置属性: " + key);
            }
        }

        return obj;
    }
}
