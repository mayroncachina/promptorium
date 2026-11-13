#!/usr/bin/env python3
"""Mede os quadros do Promptorium aberto no desktop (SPEC-049 R7).

  scripts/medir_quadros.py percorrer SAIDA.jsonl [--app CAMINHO] [--voltas N] [VAR=VALOR ...]
      Abre o app (padrão: build/linux/x64/profile/bundle/promptorium) com
      PROMPTORIUM_QUADROS=SAIDA.jsonl e as variáveis dadas, percorre as telas
      (Ctrl+1 … Ctrl+0, rolagem, paleta de comandos e atalhos) e fecha o app.
      Precisa de X11 com xdotool e wmctrl. Use um build --profile: o debug
      não mede nada de útil.

      --fotos PASTA grava um PNG de cada tela (para a varredura visual).

  scripts/medir_quadros.py resumo A.jsonl [B.jsonl]
      Resume uma medição, ou compara duas (B contra A).

Cada linha do arquivo é uma janela de 5 s com os percentis de build e raster.
O resumo junta as janelas pesando pelo número de quadros.
"""
import json
import os
import pathlib
import subprocess
import sys
import time

RAIZ = pathlib.Path(__file__).resolve().parent.parent
APP = RAIZ / 'build/linux/x64/profile/bundle/promptorium'


def sh(*args, check=False):
    return subprocess.run(args, capture_output=True, text=True, check=check)


def janela(pid, espera=40):
    """Id da janela do processo, quando ela aparecer."""
    fim = time.time() + espera
    while time.time() < fim:
        # Only a window of this very process: a title search alone also
        # matches an editor with the repository open.
        r = sh('xdotool', 'search', '--all', '--onlyvisible', '--pid', str(pid), '--name', 'Promptorium')
        for w in r.stdout.split():
            if sh('xdotool', 'getwindowpid', w).stdout.strip() == str(pid):
                return w
        time.sleep(.5)
    raise SystemExit('a janela do Promptorium não apareceu')


def foco(win):
    """Focus the app's window; stop if something else holds the focus."""
    sh('xdotool', 'windowactivate', '--sync', win)
    if sh('xdotool', 'getactivewindow').stdout.strip() != win:
        raise SystemExit('a janela do app não ficou em foco: parei para não digitar em outra janela')


def tecla(win, *teclas, pausa=.35):
    foco(win)
    for t in teclas:
        sh('xdotool', 'key', '--clearmodifiers', t)
        time.sleep(pausa)


def rolar(win, vezes=12):
    foco(win)
    sh('xdotool', 'mousemove', '--window', win, '760', '480')
    for botao in ('5', '4'):
        for _ in range(vezes):
            sh('xdotool', 'click', botao)
            time.sleep(.05)


def foto(win, pasta, nome):
    if pasta:
        pathlib.Path(pasta).mkdir(parents=True, exist_ok=True)
        sh('import', '-window', win, str(pathlib.Path(pasta) / f'{nome}.png'))


def percorrer(saida, app, voltas, extras, fotos=None):
    saida = pathlib.Path(saida).resolve()
    if saida.exists():
        saida.unlink()
    env = dict(os.environ, PROMPTORIUM_QUADROS=str(saida))
    for kv in extras:
        k, _, v = kv.partition('=')
        env[k] = v
    proc = subprocess.Popen([str(app)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        win = janela(proc.pid)
        sh('wmctrl', '-i', '-a', hex(int(win)))
        sh('xdotool', 'windowsize', win, '1440', '900')
        time.sleep(6)  # splash e primeira tela
        for _ in range(voltas):
            for d in '1234567890':
                tecla(win, f'ctrl+{d}', pausa=1.4)
                foto(win, fotos, f'tela-{d}')
                rolar(win)
                time.sleep(.6)
            tecla(win, 'ctrl+k', pausa=.8)
            foco(win)
            sh('xdotool', 'type', '--delay', '60', 'quadro')
            time.sleep(.6)
            foto(win, fotos, 'paleta')
            tecla(win, 'Escape', pausa=.8)
            tecla(win, 'ctrl+slash', pausa=1.2)
            foto(win, fotos, 'atalhos')
            tecla(win, 'Escape', pausa=.8)
        time.sleep(6)  # a última janela de 5 s
    finally:
        proc.terminate()
        try:
            proc.wait(10)
        except subprocess.TimeoutExpired:
            proc.kill()
    print(f'gravado: {saida}')
    resumo([saida])


def ler(caminho):
    return [json.loads(l) for l in pathlib.Path(caminho).read_text().splitlines() if l.strip()]


def junta(linhas):
    q = sum(l['quadros'] for l in linhas) or 1
    m = lambda k: sum(l[k] * l['quadros'] for l in linhas) / q / 1000
    return {
        'quadros': q,
        'lentos': sum(l['lentos'] for l in linhas),
        'build p50': m('build_p50_us'), 'build p90': m('build_p90_us'),
        'raster p50': m('raster_p50_us'), 'raster p90': m('raster_p90_us'),
        'raster p99 (pior janela)': max(l['raster_p99_us'] for l in linhas) / 1000,
    }


def resumo(arquivos):
    rs = [junta(ler(a)) for a in arquivos]
    nomes = [pathlib.Path(a).stem for a in arquivos]
    print(f'{"":26}' + ''.join(f'{n[:16]:>18}' for n in nomes) + ('      diferença' if len(rs) == 2 else ''))
    for k in rs[0]:
        vals = [r[k] for r in rs]
        cel = ''.join(f'{v:>18.2f}' if isinstance(v, float) else f'{v:>18}' for v in vals)
        dif = ''
        if len(rs) == 2:
            d = vals[1] - vals[0]
            dif = f'{d:>+15.2f}' if isinstance(d, float) else f'{d:>+15}'
        print(f'{k:26}{cel}{dif}')
    for r, n in zip(rs, nomes):
        print(f'{n}: {100 * r["lentos"] / r["quadros"]:.1f}% dos quadros passaram de 16,7 ms (tempos em ms)')


if __name__ == '__main__':
    a = sys.argv[1:]
    if not a or a[0] not in ('percorrer', 'resumo'):
        sys.exit(__doc__)
    if a[0] == 'resumo':
        resumo(a[1:])
    else:
        saida, app, voltas, extras, fotos, i = a[1], APP, 1, [], None, 2
        while i < len(a):
            if a[i] == '--app':
                app = pathlib.Path(a[i + 1]); i += 2
            elif a[i] == '--fotos':
                fotos = a[i + 1]; i += 2
            elif a[i] == '--voltas':
                voltas = int(a[i + 1]); i += 2
            else:
                extras.append(a[i]); i += 1
        percorrer(saida, app, voltas, extras, fotos)
