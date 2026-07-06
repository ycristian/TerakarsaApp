// Diadaptasi dari Sash_template/wwwroot/assets/plugins/sidemenu/sidemenu.js
// Hanya bagian toggle sidebar (data-bs-toggle="sidebar") yang diambil - file
// aslinya juga berisi logic horizontal-menu/mega-menu yang mengakses elemen
// (.slide-left, .slide-right, #year) yang tidak ada di struktur halaman ini
// dan akan throw error kalau di-include utuh.
(function () {
    "use strict";

    $(document).on('click', '[data-bs-toggle="sidebar"]', function (event) {
        event.preventDefault();
        $('.app').toggleClass('sidenav-toggled');
    });

    $(window).on('resize', function () {
        if ($(window).width() < 992) {
            $('.app').removeClass('sidenav-toggled');
        }
    });

    // Hover-to-expand: saat sidebar dalam mode mini (sidenav-toggled), hover
    // sementara melebarkan sidebar (CSS .sidenav-toggled-open di style.css).
    // Pakai delegated binding (bukan $('.app-sidebar').on(...)) karena elemen
    // ini di-render oleh Blazor setelah WASM load, jadi belum ada di DOM saat
    // script ini pertama kali jalan.
    $(document).on('mouseenter', '.app-sidebar', function () {
        if ($('.app').hasClass('sidenav-toggled')) {
            $('.app').addClass('sidenav-toggled-open');
        }
    });
    $(document).on('mouseleave', '.app-sidebar', function () {
        if ($('.app').hasClass('sidenav-toggled')) {
            $('.app').removeClass('sidenav-toggled-open');
        }
    });

    // Accordion toggle untuk grup menu bertingkat (SubCategory) yang dirender
    // NavMenu.razor, mis. "Master Data" > Divisi/Jabatan/Tipe Resource.
    // Delegated karena elemen ini dirender belakangan oleh Blazor setelah
    // data module selesai di-fetch dari API.
    $(document).on('click', '[data-bs-toggle="slide"]', function (event) {
        var $toggle = $(this);
        var $submenu = $toggle.next('.slide-menu');
        if ($submenu.length === 0) {
            return;
        }

        event.preventDefault();

        var animationSpeed = 300;
        var $parentLi = $toggle.parent('li');

        if ($submenu.is(':visible')) {
            $submenu.slideUp(animationSpeed, function () {
                $submenu.removeClass('open');
            });
            $parentLi.removeClass('is-expanded');
            return;
        }

        var $siblingList = $toggle.parents('ul').first();
        $siblingList.find('> li > ul.slide-menu:visible').slideUp(animationSpeed).removeClass('open');
        $siblingList.find('> li.is-expanded').removeClass('is-expanded');

        $submenu.slideDown(animationSpeed, function () {
            $submenu.addClass('open');
        });
        $parentLi.addClass('is-expanded');
    });
})();
