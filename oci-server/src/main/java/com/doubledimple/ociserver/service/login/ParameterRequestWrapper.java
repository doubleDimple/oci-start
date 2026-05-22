package com.doubledimple.ociserver.service.login;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletRequestWrapper;
import java.util.HashMap;
import java.util.Map;

public class ParameterRequestWrapper extends HttpServletRequestWrapper {
    private final Map<String, String[]> params = new HashMap<>();

    public ParameterRequestWrapper(HttpServletRequest request) {
        super(request);
        this.params.putAll(request.getParameterMap());
    }

    public void setParameter(String name, String value) {
        this.params.put(name, new String[]{value});
    }

    @Override
    public String getParameter(String name) {
        String[] values = params.get(name);
        return (values == null || values.length == 0) ? null : values[0];
    }

    @Override
    public Map<String, String[]> getParameterMap() {
        return params;
    }

    @Override
    public String[] getParameterValues(String name) {
        return params.get(name);
    }
}
