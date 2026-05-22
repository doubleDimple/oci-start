package com.doubledimple.ociserver.controller;

import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

/**
 * @author doubleDimple
 * @date 2024:11:24日 10:28
 */
@Controller
public class HomeController  extends BaseController{

    @GetMapping("/")
    public String home() {
        return "redirect:/login";  // 或者直接返回 "redirect:/tenants/list"
    }


    @GetMapping("/delayTest")
    public String showChatPage(Model model){
        model.addAttribute("activePage", "api-delayTest");
        return "speed_test";
    }
}
