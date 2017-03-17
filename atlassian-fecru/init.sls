{% from 'atlassian-fecru/map.jinja' import fecru with context %}

include:
  - java

fecru:
  file.managed:
    - name: /etc/systemd/system/atlassian-fecru.service
    - source: salt://atlassian-fecru/files/atlassian-fecru.service
    - template: jinja
    - defaults:
        config: {{ fecru }}

  module.wait:
    - name: service.systemctl_reload
    - watch:
      - file: fecru

  group.present:
    - name: {{ fecru.group }}

  user.present:
    - name: {{ fecru.user }}
    - home: {{ fecru.dirs.home }}
    - gid: {{ fecru.group }}
    - require:
      - group: fecru
      - file: fecru-dir

  service.running:
    - name: atlassian-fecru
    - enable: True
    - require:
      - file: fecru

fecru-graceful-down:
  service.dead:
    - name: atlassian-fecru
    - require:
      - module: fecru
    - prereq:
      - file: fecru-install

fecru-download:
  cmd.run:
    - name: "curl -L --silent '{{ fecru.url }}' > '{{ fecru.source }}'"
    - unless: "test -f '{{ fecru.source }}'"
    - prereq:
      - cmd: fecru-install

fecru-install:
  pkg.installed:
    - pkgs:
      - unzip
      - git

  cmd.run:
    - name: "unzip -q '{{ fecru.source }}'"
    - cwd: {{ fecru.dirs.extract }}
    - unless: "test -d '{{ fecru.dirs.current_install }}'"
    - require:
      - file: fecru-extractdir
      - pkg: fecru-install

{# archive.extracted does not preserve permissions with zip files (https://github.com/saltstack/salt/issues/27207)
  archive.extracted:
    - name: {{ fecru.dirs.extract }}
    - source: {{ fecru.url }}
    - source_hash: {{ fecru.url_hash }}
    - archive_format: zip
    - if_missing: {{ fecru.dirs.current_install }}
    - user: root
    - group: root
    - keep: True
    - require:
      - file: fecru-extractdir
      - pkg: fecru-install
#}

  file.symlink:
    - name: {{ fecru.dirs.install }}
    - target: {{ fecru.dirs.current_install }}
    - require:
      - cmd: fecru-install
    - watch_in:
      - service: fecru

fecru-dir:
  file.directory:
    - name: {{ fecru.dir }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

fecru-home:
  file.directory:
    - name: {{ fecru.dirs.home }}
    - user: {{ fecru.user }}
    - group: {{ fecru.group }}
    - mode: 755
    - makedirs: True

fecru-extractdir:
  file.directory:
    - name: {{ fecru.dirs.extract }}
    - use:
      - file: fecru-dir

fecru-scriptdir:
  file.directory:
    - name: {{ fecru.dirs.scripts }}
    - use:
      - file: fecru-dir

{% for file in [ 'env.sh', 'start.sh', 'stop.sh' ] %}
fecru-script-{{ file }}:
  file.managed:
    - name: {{ fecru.dirs.scripts }}/{{ file }}
    - source: salt://atlassian-fecru/files/{{ file }}
    - user: {{ fecru.user }}
    - group: {{ fecru.group }}
    - mode: 755
    - template: jinja
    - defaults:
        config: {{ fecru }}
    - require:
      - file: fecru-scriptdir
    - watch_in:
      - service: fecru
{% endfor %}

fecru-fisheyectl.sh-pidfile-patch:
  pkg.installed:
    - name: patch

  file.managed:
    - name: /tmp/fisheyectl.sh.patch
    - source: salt://atlassian-fecru/files/fisheyectl.sh.patch

  cmd.run:
    - name: patch -N --silent < /tmp/fisheyectl.sh.patch
    - onlyif: nohup patch -N --dry-run --silent < /tmp/fisheyectl.sh.patch 2>/dev/null
    - cwd: {{ fecru.dirs.install }}/bin
    - require:
      - pkg: fecru-fisheyectl.sh-pidfile-patch
      - file: fecru-fisheyectl.sh-pidfile-patch
      - file: fecru-install
    - require_in:
      - service: fecru

fecru-config-xml:
  cmd.run:
    - name: cp {{ fecru.dirs.install }}/config.xml {{ fecru.dirs.home }}/config.xml
    - unless: test -f {{ fecru.dirs.home }}/config.xml
    - require:
      - file: fecru-install
      - file: fecru-home

  file.blockreplace:
    - name: {{ fecru.dirs.home }}/config.xml
    - marker_start: "<web-server"
    - marker_end: "</web-server>"
    - require:
      - file: fecru-config-xml-chmod
    - watch_in:
      - service: fecru

fecru-config-xml-chmod:
  file.managed:
    - name: {{ fecru.dirs.home }}/config.xml
    - user: {{ fecru.user }}
    - group: {{ fecru.group }}
    - replace: False
    - mode: 640
    - require:
      - cmd: fecru-config-xml

{% if 'ajp_port' in fecru %}
fecru-config-xml-ajp-bind:
  file.accumulated:
    - name: fecru-config-accumulator
    - filename: {{ fecru.dirs.home }}/config.xml
    - text: '<ajp13 bind=":{{ fecru.ajp_port }}"/>'
    - require_in:
      - file: fecru-config-xml
{% endif %}

{% if 'http_port' in fecru %}
fecru-config-xml-http-bind:
  file.accumulated:
    - name: fecru-config-accumulator
    - filename: {{ fecru.dirs.home }}/config.xml
    - text: |
        <http bind=":{{ fecru.http_port }}"
          {%- if 'http_proxyPort' in fecru %} proxy-port="{{ fecru.http_proxyPort }}"{% endif %}
          {%- if 'http_scheme' in fecru %} proxy-scheme="{{ fecru.http_scheme }}"{% endif %}
          {%- if 'http_proxyName' in fecru %} proxy-host="{{ fecru.http_proxyName }}"{% endif -%}
        />
    - require_in:
      - file: fecru-config-xml
{% endif %}
