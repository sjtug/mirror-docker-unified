import requests

"""
Here we take Ubuntu repo as an example. It should be served on both http
and https. Caddy should handle the redirections correctly.
"""

BASE_URL = "ftp.sjtu.edu.cn"

def test_ubuntu_http_base():
    response = requests.get(f"http://{BASE_URL}/ubuntu")
    assert response.history
    assert response.url == f"http://{BASE_URL}/ubuntu/"

def test_ubuntu_http_dir():
    response = requests.get(f"http://{BASE_URL}/ubuntu/pool")
    assert response.history
    assert response.url == f"http://{BASE_URL}/ubuntu/pool/"

def test_ubuntu_https_base():
    response = requests.get(f"https://{BASE_URL}/ubuntu")
    assert response.history
    assert response.url == f"https://{BASE_URL}/ubuntu/"

def test_ubuntu_https_dir():
    response = requests.get(f"https://{BASE_URL}/ubuntu/pool")
    assert response.history
    assert response.url == f"https://{BASE_URL}/ubuntu/pool/"

"""
Here we take conda repo as an example. It should be served only on https
interface. All http request should be redirected to https.
"""

BASE_URL_2 = "mirrors.sjtug.sjtu.edu.cn"

def test_conda_http_base():
    response = requests.get(f"http://{BASE_URL_2}/anaconda")
    assert response.history
    assert response.url == f"https://{BASE_URL_2}/anaconda/"

def test_conda_http_dir():
    response = requests.get(f"http://{BASE_URL_2}/anaconda/cloud")
    assert response.history
    assert response.url == f"https://{BASE_URL_2}/anaconda/cloud/"

def test_conda_https_base():
    response = requests.get(f"https://{BASE_URL_2}/anaconda")
    assert response.history
    assert response.url == f"https://{BASE_URL_2}/anaconda/"

def test_conda_https_dir():
    response = requests.get(f"https://{BASE_URL_2}/anaconda/cloud")
    assert response.history
    assert response.url == f"https://{BASE_URL_2}/anaconda/cloud/"

def test_conda_file():
    response = requests.get(f"http://{BASE_URL_2}/anaconda/cloud/pytorch/noarch/repodata.json")
    assert response.history
    assert response.url == f"https://{BASE_URL_2}/anaconda/cloud/pytorch/noarch/repodata.json"

"""
And for our frontend, it should always be available on https.
"""

BASE_URL_3 = "mirrors.sjtug.sjtu.edu.cn"

def test_frontend_base():
    response = requests.get(f"http://{BASE_URL_3}")
    assert response.history
    assert response.url == f"https://{BASE_URL_3}/"

def test_frontend_base():
    response = requests.get(f"http://{BASE_URL_3}/index.html")
    assert response.history
    assert response.url == f"https://{BASE_URL_3}/"

def test_lug_base():
    response = requests.get(f"http://{BASE_URL_3}/lug/v1/manager/summary")
    assert response.history
    assert response.url == f"https://{BASE_URL_3}/lug/v1/manager/summary"

"""
Also an edge case, we should never concat two directories
"""

def test_anaconda_concat():
    response = requests.get(f"http://{BASE_URL_3}/anacondacloud/pytorch/noarch/repodata.json")
    assert response.status_code == 404
