/* (C) 2013 SZABO Gergely <szg@subogero.com> GNU AGPL v3 */
con = {};
con.refresh = false;

con.send = function(cmd) {
    var req = new XMLHttpRequest();
    req.open("POST", "S", false);
    req.setRequestHeader("Content-type","application/json");
    req.send(JSON.stringify({cmd: cmd}));
    con.status2html(JSON.parse(req.responseText));
}

con.getStatus = function() {
    var req = new XMLHttpRequest();
    req.onreadystatechange = function() {
        if (req.readyState == 4 && req.status == 200) {
            con.status2html(JSON.parse(req.responseText));
        }
    }
    req.open("GET", "S" + Date.now().toString(), true);
    req.send();
    if (con.refresh) {
        setTimeout("con.getStatus()", 2000);
    }
}

con.status2html = function(st) {
    var html = '<p class="even">';
    if (st.image) {
        html += '<img style="float:right" height="80" src="' + st.image + '">';
    }
    html += st.doing + ' ' + con.s2t(st.at) + ' / ' + con.s2t(st.of) + '<br>';
    if (st.what.charAt(0) == '/') {
        html += st.what.substring(1).split('/').join('<br>');
    } else {
        html += st.what;
    }
    html += '</p>';
    var bar = (st.of == 0    ? 0
             : st.at > st.of ? 100
             :                 100 * st.at/st.of).toString() + '%';
    html += '<div id="nowplaying"><div style="width:' + bar + '"></div></div>';
    for (i = 0; i < st.list.length; i++) {
        var c = st.list[i] == st.what ? 'now' : i % 2 ? 'odd' : 'even';
        html += '<p class="' + c + '">' + st.list[i] + '</p>';
    }
    document.getElementById("st").innerHTML = html;
}

con.s2t = function(s) {
    var t = new Date(s * 1000);
    return t.toUTCString().split(' ')[4];
}

function Tab(name, callback) {
    this.name  = name;
    this.content = document.getElementById(name);
    this.button = document.getElementById('b' + name);
    this.callback = callback;
    this.toggle = function(on) {
        this.content.style.display = on ? 'block' : 'none';
        this.button.className = on ? 'tabhi' : 'tablo';
        if (on) {
            this.callback();
        }
    };
}

con.browse = function(what) {
    if (typeof con.tabs === 'undefined') {
        con.tabs = [
            new Tab('list', con.getStatus),
            new Tab('home', rpi.ls),
            new Tab('fm', rpifm.sendcmds),
            new Tab('yt'),
            new Tab('help'),
        ];
    }
    con.refresh = what == 'list';
    for (var i = 0; i < con.tabs.length; i++) {
        con.tabs[i].toggle(con.tabs[i].name == what);
    }
}
