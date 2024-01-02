

from typing import Callable, Generator, Iterable, TypeVar
from attr import define
from bleak import BleakScanner

T = TypeVar('T')
ExceptionT = TypeVar('ExceptionT', bound=Exception)

StatePoller = Callable[[], Iterable[T]]

RetryCondition = Callable[[T], bool]



def retr


@define
class 