import requests

BASE_URL = "mirrors.sjtug.sjtu.edu.cn"

"""
Here we take Raspbian repo as an example. It should be served on both http
and https. Caddy should handle the redirections correctly.
"""


def test_raspbian_http_base():
    response = requests.get(f"http://{BASE_URL}/raspbian")
    assert response.history
    assert response.url == f"http://{BASE_URL}/raspbian/"


def test_raspbian_http_dir():
    response = requests.get(f"http://{BASE_URL}/raspbian/raspbian/pool")
    assert response.history
    assert response.url == f"http://{BASE_URL}/raspbian/raspbian/pool/"


def test_raspbian_https_base():
    response = requests.get(f"https://{BASE_URL}/raspbian")
    assert response.history
    assert response.url == f"https://{BASE_URL}/raspbian/"


def test_raspbian_https_dir():
    response = requests.get(f"https://{BASE_URL}/raspbian/raspbian/pool")
    assert response.history
    assert response.url == f"https://{BASE_URL}/raspbian/raspbian/pool/"


"""
Here we take conda repo as an example. It should be served only on https
interface. All http request should be redirected to https.
"""


def test_conda_http_base():
    response = requests.get(f"http://{BASE_URL}/anaconda")
    assert response.history
    assert response.url == f"https://{BASE_URL}/anaconda/"


def test_conda_http_dir():
    response = requests.get(f"http://{BASE_URL}/anaconda/cloud")
    assert response.history
    assert response.url == f"https://{BASE_URL}/anaconda/cloud/"


def test_conda_https_base():
    response = requests.get(f"https://{BASE_URL}/anaconda")
    assert response.history
    assert response.url == f"https://{BASE_URL}/anaconda/"


def test_conda_https_dir():
    response = requests.get(f"https://{BASE_URL}/anaconda/cloud")
    assert response.history
    assert response.url == f"https://{BASE_URL}/anaconda/cloud/"


def test_conda_file():
    response = requests.get(
        f"http://{BASE_URL}/anaconda/cloud/pytorch/noarch/repodata.json"
    )
    assert response.history
    assert (
        response.url
        == f"https://{BASE_URL}/anaconda/cloud/pytorch/noarch/repodata.json"
    )


"""
And for our frontend, it should always be available on https.
"""


def test_frontend_base():
    response = requests.get(f"http://{BASE_URL}")
    assert response.history
    assert response.url == f"https://{BASE_URL}/"


def test_frontend_docs():
    response = requests.get(f"http://{BASE_URL}/docs/anaconda")
    assert response.history
    assert response.status_code == 200
    assert response.url == f"https://{BASE_URL}/docs/anaconda"


def test_lug_base():
    response = requests.get(f"http://{BASE_URL}/lug/v1/manager/summary")
    assert response.history
    assert response.url == f"https://{BASE_URL}/lug/v1/manager/summary"


"""
Also an edge case, we should never concat two directories
"""


def test_anaconda_concat():
    response = requests.get(
        f"http://{BASE_URL}/anacondacloud/pytorch/noarch/repodata.json"
    )
    assert response.status_code == 404
