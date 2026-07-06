(function() {
    'use strict'

    let stickyClass = "sticky-pin",
     stickyPos = 66; //Distance from the top of the window.

    function jumpsPrevent() {
        let stickyElement = $(".sticky");
        if (!stickyElement.length) return;
        let stickyHeight = stickyElement.innerHeight();
        stickyElement.css({ "margin-bottom": "-" + stickyHeight + "px" });
        stickyElement.next().css({ "padding-top": +stickyHeight + "px" });
    };
    window.jumpsPrevent = jumpsPrevent;
    jumpsPrevent(); //Run.

    //Function trigger:
    $(window).on('resize', function() {
        jumpsPrevent();

    });

    //Sticker function:
    function stickerFn() {
        let winTop = $(window).scrollTop();
        //Check element position:
        winTop >= stickyPos ?
            $(".sticky").addClass('stickyClass') :
            $(".sticky").removeClass('stickyClass') //Boolean class switcher.
    };
    stickerFn(); //Run.
    $(window).on('scroll',function() {
        stickerFn();
    });
    
    $('.app-sidebar').on('scroll', function() {
        let s = $(".app-sidebar .ps__rail-y");
        if (s[0].style.top.split('px')[0] <= 60 ) {
            $('.app-sidebar').removeClass('sidemenu-scroll')
        } else {
            $('.app-sidebar').addClass('sidemenu-scroll')
        }

    })

})();
