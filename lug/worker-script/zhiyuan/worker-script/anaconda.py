#!/usr/bin/env python3

import concurrent.futures as futures
import urllib.request as request
from urllib.parse import urljoin
from urllib.error import HTTPError
from http.client import HTTPException
import shutil
import os
import sys
import json
import hashlib
import traceback
from json import JSONDecodeError

import time
from functools import wraps


def retry(ExceptionToCheck, tries=4, delay=3, backoff=2, logger=None):
    """Retry calling the decorated function using an exponential backoff.

    http://www.saltycrane.com/blog/2009/11/trying-out-retry-decorator-python/
    original from: http://wiki.python.org/moin/PythonDecoratorLibrary#Retry

    :param ExceptionToCheck: the exception to check. may be a tuple of
        exceptions to check
    :type ExceptionToCheck: Exception or tuple
    :param tries: number of times to try (not retry) before giving up
    :type tries: int
    :param delay: initial delay between retries in seconds
    :type delay: int
    :param backoff: backoff multiplier e.g. value of 2 will double the delay
        each retry
    :type backoff: int
    :param logger: logger to use. If None, print
    :type logger: logging.Logger instance
    """

    def deco_retry(f):
        @wraps(f)
        def f_retry(*args, **kwargs):
            mtries, mdelay = tries, delay
            while mtries > 1:
                try:
                    return f(*args, **kwargs)
                except ExceptionToCheck as e:
                    msg = "%s, Retrying in %d seconds..." % (str(e), mdelay)
                    if logger:
                        logger.warning(msg)
                    else:
                        sys.stderr.write(msg + "\n")
                    time.sleep(mdelay)
                    mtries -= 1
                    mdelay *= backoff
            try:
                return f(*args, **kwargs)
            except ExceptionToCheck as e:
                msg = "Failed last attempt %s, %s %s" % (str(e), str(args), str(kwargs))
                if logger:
                    logger.warning(msg)
                else:
                    sys.stderr.write(msg + "\n")
                raise

        return f_retry  # true decorator

    return deco_retry


@retry((OSError, HTTPException), tries=4, delay=3, backoff=2)
def urlopen_failsafe(*args, **kwargs):
    return request.urlopen(*args, **kwargs)


@retry((OSError, JSONDecodeError, HTTPException), tries=4, delay=3, backoff=2)
def jsonurlopen_failsafe(*args, **kwargs):
    result = request.urlopen(*args, **kwargs)
    text = result.read().decode("utf-8")
    json.loads(text)
    return text


def verify_file(
    filepath: str,
    md5: str,
    size: int,
    skip_md5: bool = False,
    output_fail_reason: bool = False,
) -> int:
    verify_ok = False
    if os.path.exists(filepath) and os.stat(filepath).st_size == size:
        if skip_md5:
            verify_ok = True
        else:
            with open(filepath, "rb") as f:
                actual_md5 = hashlib.md5(f.read()).hexdigest()
                if actual_md5 == md5:
                    verify_ok = True
                else:
                    if output_fail_reason:
                        sys.stderr.write(
                            "Verify failed: MD5 mismatch of {}: Expected {}, Got {}\n".format(
                                filemath,  # noqa: F821
                                md5,
                                actual_md5,
                            )
                        )
    else:
        if output_fail_reason:
            if not os.path.exists(filepath):
                sys.stderr.write("Verify failed: {} not exists\n".format(filepath))
            else:
                sys.stderr.write(
                    "Verify failed: {} size mismatch: Expected {} Actual {}\n".format(
                        filepath, size, os.stat(filepath).st_size
                    )
                )
    return verify_ok


class VerifyError(RuntimeError):
    def __init__(self, msg):
        self.msg = msg

    def __str__(self):
        return "Failed to verify {}".format(self.msg)


@retry(
    (VerifyError, ValueError, ConnectionError, EnvironmentError, HTTPException),
    tries=3,
    delay=3,
    backoff=2,
)
def download_file(url_root: str, target_dir: str, name: str, md5: str, size: int):
    filepath = os.path.join(target_dir, name)
    tmp_filepath = os.path.join(target_dir, "." + name)
    verify_ok = verify_file(filepath, md5, size, skip_md5=True)
    if verify_ok:
        print("{} already exists! skippped".format(filepath))
        return
    else:
        print("{} not exist or contents mismatch. Try to download...".format(filepath))
    result = urlopen_failsafe(urljoin(url_root, name))
    with result, open(tmp_filepath, "wb") as f:
        shutil.copyfileobj(result, f)
    post_verify_ok = verify_file(
        tmp_filepath, md5, size, skip_md5=False, output_fail_reason=True
    )
    if not post_verify_ok:
        os.remove(tmp_filepath)
        raise VerifyError(filepath)
    os.rename(tmp_filepath, filepath)
    print("Suceeded to download {}".format(filepath))


DOWNLOAD_FAILED_THRESHOLD = 50  # <=50 errors are acceptable


def download_repo(executor, url_root: str, target_dir: str):
    if not os.path.exists(target_dir):
        os.makedirs(target_dir)
    result = jsonurlopen_failsafe(urljoin(url_root, "repodata.json"))
    print("Downloading metafiles at {}".format(urljoin(url_root, "repodata.json")))
    tmp_result_path = os.path.join(target_dir, ".repodata.json")
    with open(tmp_result_path, "w", encoding="utf-8") as f:
        f.write(result)
    result_bz2 = urlopen_failsafe(urljoin(url_root, "repodata.json.bz2"))
    tmp_result_bz2_path = os.path.join(target_dir, ".repodata.json.bz2")
    with result_bz2, open(tmp_result_bz2_path, "wb") as f:
        shutil.copyfileobj(result_bz2, f)
    current_repodata_enabled = False
    try:
        result_current = jsonurlopen_failsafe(  # noqa: F841
            urljoin(url_root, "current_repodata.json")
        )
        tmp_result_current_path = os.path.join(target_dir, ".current_repodata.json")
        with open(tmp_result_current_path, "w", encoding="utf-8") as f:
            f.write(result)
        current_repodata_enabled = True
    except HTTPError as e:
        print("Failed to acquire current_repodata of {}, {}".format(url_root, e))
    print("Succeeded to acquire repodata of {}".format(url_root))
    download_failed_cnt = 0
    with open(tmp_result_path, "r") as f:
        j = json.load(f)
        if "packages" not in j:
            print("No package in repo {}".format(url_root))
            packages = {}
        else:
            packages = j["packages"]
            if "packages.conda" in j:
                packages_conda = j["packages.conda"]
                packages.update(packages_conda)
        download_futures = {}
        for name, value in packages.items():
            print("Submitted to download {}/{}".format(url_root, name))
            download_futures[
                executor.submit(
                    download_file,
                    url_root,
                    target_dir,
                    name,
                    value["md5"],
                    value["size"],
                )
            ] = name
        for future in futures.as_completed(download_futures):
            name = download_futures[future]
            try:
                future.result()
            except Exception as exc:
                sys.stderr.write(
                    "Failed to download {}/{}: {} | {} \n".format(
                        url_root, name, exc, traceback.format_exc()
                    )
                )
                download_failed_cnt += 1
        if download_failed_cnt > DOWNLOAD_FAILED_THRESHOLD:
            raise RuntimeError("Failed to sync repos at {}".format(url_root))
        os.rename(tmp_result_path, os.path.join(target_dir, "repodata.json"))
        os.rename(tmp_result_bz2_path, os.path.join(target_dir, "repodata.json.bz2"))
        if current_repodata_enabled:
            os.rename(
                tmp_result_current_path,
                os.path.join(target_dir, "current_repodata.json"),
            )
        print("Remove unused files...")
        for filename in os.listdir(target_dir):
            if filename.startswith(".") or (
                filename.endswith(".bz2")
                and filename != "repodata.json.bz2"
                and filename not in packages
            ):
                delta_since_last_modify = time.time() - os.path.getmtime(
                    os.path.join(target_dir, filename)
                )
                if delta_since_last_modify <= 86400:
                    print(
                        "Skipped {}. Since last modify only occurs {} seconds ago.".format(
                            filename, delta_since_last_modify
                        )
                    )
                    continue
                print("Deleting {}".format(filename))
                os.remove(os.path.join(target_dir, filename))
    print("Succeeded to sync {}".format(url_root))


REPOS = {}
PATH_BASE = "/tmp"
THREAD_NUM = 16


def get_config_from_env():
    global THREAD_NUM, PATH_BASE, REPOS
    j = json.loads(os.getenv("LUG_config_json"))
    if "thread_num" in j:
        THREAD_NUM = j["thread_num"]
    if "path" in j:
        PATH_BASE = j["path"]
    for k, v in j.items():
        if isinstance(v, str) and v.startswith("http"):
            REPOS[k] = v


if __name__ == "__main__":
    get_config_from_env()
    with futures.ThreadPoolExecutor(THREAD_NUM) as executor:
        all_ok = True
        repo_futures = {}
        for name, url in REPOS.items():
            repo_futures[
                executor.submit(
                    download_repo, executor, url, os.path.join(PATH_BASE, name)
                )
            ] = name
        for future in repo_futures:
            name = repo_futures[future]
            try:
                future.result()
            except Exception:
                sys.stderr.write(
                    "Failed to download {}: {} | {}".format(
                        name, future, traceback.format_exc()
                    )
                )
                all_ok = False
        sys.exit(0 if all_ok else 1)
