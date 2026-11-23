<script setup lang="ts">
import { computed } from "vue";
import ActivityIcon from "../icons/ActivityIcon.svg?raw";
import ArrowLeftIcon from "../icons/ArrowLeftIcon.svg?raw";
import AttachFileIcon from "../icons/AttachFileIcon.svg?raw";
import BoltIcon from "../icons/BoltIcon.svg?raw";
import ArrowRightIcon from "../icons/ArrowRightIcon.svg?raw";
import AvatarIcon from "../icons/AvatarIcon.svg?raw";
import BlockFilterIcon from "../icons/BlockFilterIcon.svg?raw";
import BriefcaseBusinessIcon from "../icons/BriefcaseBusinessIcon.svg?raw";
import BuildingIcon from "../icons/BuildingIcon.svg?raw";
import CalendarIcon from "../icons/CalendarIcon.svg?raw";
import CalendarClockIcon from "../icons/CalendarClockIcon.svg?raw";
import CalendarMonthIcon from "../icons/CalendarMonthIcon.svg?raw";
import CalendarRangeIcon from "../icons/CalendarRangeIcon.svg?raw";
import CalendarTodayIcon from "../icons/CalendarTodayIcon.svg?raw";
import CalendarWeekIcon from "../icons/CalendarWeekIcon.svg?raw";
import ChartLineIcon from "../icons/ChartLineIcon.svg?raw";
import CheckIcon from "../icons/CheckIcon.svg?raw";
import CollapseAllIcon from "../icons/CollapseAllIcon.svg?raw";
import ChevronDownIcon from "../icons/ChevronDownIcon.svg?raw";
import ChevronFirstIcon from "../icons/ChevronFirstIcon.svg?raw";
import ChevronLastIcon from "../icons/ChevronLastIcon.svg?raw";
import ChevronLeftIcon from "../icons/ChevronLeftIcon.svg?raw";
import ChevronRightIcon from "../icons/ChevronRightIcon.svg?raw";
import ChevronsCollapseIcon from "../icons/ChevronsCollapseIcon.svg?raw";
import ChevronsExpandIcon from "../icons/ChevronsExpandIcon.svg?raw";
import ChevronUpIcon from "../icons/ChevronUpIcon.svg?raw";
import CircleArrowRightIcon from "../icons/CircleArrowRightIcon.svg?raw";
import CircleCheckIcon from "../icons/CircleCheckIcon.svg?raw";
import CircleErrorIcon from "../icons/CircleErrorIcon.svg?raw";
import CircleHelpIcon from "../icons/CircleHelpIcon.svg?raw";
import CirclePlusIcon from "../icons/CirclePlusIcon.svg?raw";
import CircleUserIcon from "../icons/CircleUserIcon.svg?raw";
import ClockIcon from "../icons/ClockIcon.svg?raw";
import CloudUploadIcon from "../icons/CloudUploadIcon.svg?raw";
import ConstructionIcon from "../icons/ConstructionIcon.svg?raw";
import CrossIcon from "../icons/CrossIcon.svg?raw";
import DashboardIcon from "../icons/DashboardIcon.svg?raw";
import DownloadIcon from "../icons/DownloadIcon.svg?raw";
import ExpandAllIcon from "../icons/ExpandAllIcon.svg?raw";
import ExpandIcon from "../icons/ExpandIcon.svg?raw";
import FileIcon from "../icons/FileIcon.svg?raw";
import FilterIcon from "../icons/FilterIcon.svg?raw";
import FlashlightIcon from "../icons/FlashlightIcon.svg?raw";
import FlashlightOffIcon from "../icons/FlashlightOffIcon.svg?raw";
import FlowIcon from "../icons/FlowIcon.svg?raw";
import FullScreenIcon from "../icons/FullScreenIcon.svg?raw";
import FullWidthIcon from "../icons/FullWidthIcon.svg?raw";
import GraphIcon from "../icons/GraphIcon.svg?raw";
import GroupIcon from "../icons/GroupIcon.svg?raw";
import HeartIcon from "../icons/HeartIcon.svg?raw";
import HouseAddIcon from "../icons/HouseAddIcon.svg?raw";
import ImageIcon from "../icons/ImageIcon.svg?raw";
import InfoIcon from "../icons/InfoIcon.svg?raw";
import KeyboardIcon from "../icons/KeyboardIcon.svg?raw";
import ListFilterIcon from "../icons/ListFilterIcon.svg?raw";
import ListIcon from "../icons/ListIcon.svg?raw";
import LockIcon from "../icons/LockIcon.svg?raw";
import LockOpenIcon from "../icons/LockOpenIcon.svg?raw";
import LogoIcon from "../icons/LogoIcon.svg?raw";
import LowPriorityIcon from "../icons/LowPriorityIcon.svg?raw";
import MapPinIcon from "../icons/MapPinIcon.svg?raw";
import MenuIcon from "../icons/MenuIcon.svg?raw";
import MessageWarningIcon from "../icons/MessageWarningIcon.svg?raw";
import MicIcon from "../icons/MicIcon.svg?raw";
import MinusIcon from "../icons/MinusIcon.svg?raw";
import MoreVertIcon from "../icons/MoreVertIcon.svg?raw";
import MusicIcon from "../icons/MusicIcon.svg?raw";
import PlayIcon from "../icons/PlayIcon.svg?raw";
import VolumeUpIcon from "../icons/VolumeUpIcon.svg?raw";
import VolumeOffIcon from "../icons/VolumeOffIcon.svg?raw";
import NewspaperIcon from "../icons/NewspaperIcon.svg?raw";
import NotFoundIcon from "../icons/NotFoundIcon.svg?raw";
import NotificationIcon from "../icons/NotificationIcon.svg?raw";
import OpenInNewIcon from "../icons/OpenNewIcon.svg?raw";
import PauseIcon from "../icons/PauseIcon.svg?raw";
import PencilIcon from "../icons/PencilIcon.svg?raw";
import PentagonIcon from "../icons/PentagonIcon.svg?raw";
import PlusIcon from "../icons/PlusIcon.svg?raw";
import PrinterIcon from "../icons/PrinterIcon.svg?raw";
import QrCodeIcon from "../icons/QRCodeIcon.svg?raw";
import RedoIcon from "../icons/RedoIcon.svg?raw";
import RepeatIcon from "../icons/RepeatIcon.svg?raw";
import SearchIcon from "../icons/SearchIcon.svg?raw";
import SdkIcon from "../icons/SdkIcon.svg?raw";
import SendIcon from "../icons/SendIcon.svg?raw";
import SettingsIcon from "../icons/SettingsIcon.svg?raw";
import SidebarIcon from "../icons/SidebarIcon.svg?raw";
import ShareIcon from "../icons/ShareIcon.svg?raw";
import ShieldCheckIcon from "../icons/ShieldCheckIcon.svg?raw";
import ShieldUserIcon from "../icons/ShieldUserIcon.svg?raw";
import ShrinkIcon from "../icons/ShrinkIcon.svg?raw";
import SortIcon from "../icons/SortIcon.svg?raw";
import SquareActivityIcon from "../icons/SquareActivityIcon.svg?raw";
import SquareDashedIcon from "../icons/SquareDashedIcon.svg?raw";
import StoreIcon from "../icons/StoreIcon.svg?raw";
import TrashIcon from "../icons/TrashIcon.svg?raw";
import TriangleAlertIcon from "../icons/TriangleAlertIcon.svg?raw";
import UndoIcon from "../icons/UndoIcon.svg?raw";
import UploadIcon from "../icons/UploadIcon.svg?raw";
import UsersIcon from "../icons/UsersIcon.svg?raw";
import WebhooksIcon from "../icons/WebhooksIcon.svg?raw";
import ZoomInIcon from "../icons/ZoomInIcon.svg?raw";
import ZoomOutIcon from "../icons/ZoomOutIcon.svg?raw";
import AlignLeftIcon from "../icons/AlignLeftIcon.svg?raw";
import AlignCenterIcon from "../icons/AlignCenterIcon.svg?raw";
import AlignRightIcon from "../icons/AlignRightIcon.svg?raw";
import AlignJustifyIcon from "../icons/AlignJustifyIcon.svg?raw";
import CalendarPlusIcon from "../icons/CalendarPlusIcon.svg?raw";
import CreditCardIcon from "../icons/CreditCardIcon.svg?raw";
import EllipsisHIcon from "../icons/EllipsisHIcon.svg?raw";
import ChevronsLeftIcon from "../icons/ChevronsLeftIcon.svg?raw";
import ChevronsRightIcon from "../icons/ChevronsRightIcon.svg?raw";
import ArrowUpIcon from "../icons/ArrowUpIcon.svg?raw";
import ArrowDownIcon from "../icons/ArrowDownIcon.svg?raw";
import ArrowsHorizontalIcon from "../icons/ArrowsHorizontalIcon.svg?raw";
import AtIcon from "../icons/AtIcon.svg?raw";
import BookmarkIcon from "../icons/BookmarkIcon.svg?raw";
import BoxIcon from "../icons/BoxIcon.svg?raw";
import CheckSquareIcon from "../icons/CheckSquareIcon.svg?raw";
import SquareIcon from "../icons/SquareIcon.svg?raw";
import CodeIcon from "../icons/CodeIcon.svg?raw";
import CommentIcon from "../icons/CommentIcon.svg?raw";
import CopyIcon from "../icons/CopyIcon.svg?raw";
import FilePdfIcon from "../icons/FilePdfIcon.svg?raw";
import HashtagIcon from "../icons/HashtagIcon.svg?raw";
import Heading1Icon from "../icons/Heading1Icon.svg?raw";
import Heading2Icon from "../icons/Heading2Icon.svg?raw";
import Heading3Icon from "../icons/Heading3Icon.svg?raw";
import Heading4Icon from "../icons/Heading4Icon.svg?raw";
import IdCardIcon from "../icons/IdCardIcon.svg?raw";
import ImagesIcon from "../icons/ImagesIcon.svg?raw";
import LinkIcon from "../icons/LinkIcon.svg?raw";
import UnlinkIcon from "../icons/UnlinkIcon.svg?raw";
import PaletteIcon from "../icons/PaletteIcon.svg?raw";
import RefreshIcon from "../icons/RefreshIcon.svg?raw";
import SitemapIcon from "../icons/SitemapIcon.svg?raw";
import StopCircleIcon from "../icons/StopCircleIcon.svg?raw";
import TableIcon from "../icons/TableIcon.svg?raw";
import TextHeightIcon from "../icons/TextHeightIcon.svg?raw";
import VideoIcon from "../icons/VideoIcon.svg?raw";
import GripVerticalIcon from "../icons/GripVerticalIcon.svg?raw";
import FolderIcon from "../icons/FolderIcon.svg?raw";
import FileTextIcon from "../icons/FileTextIcon.svg?raw";
import FileMarkdownIcon from "../icons/FileMarkdownIcon.svg?raw";
import FileWordIcon from "../icons/FileWordIcon.svg?raw";
import FileSheetIcon from "../icons/FileSheetIcon.svg?raw";
import FileCsvIcon from "../icons/FileCsvIcon.svg?raw";
import FileSlidesIcon from "../icons/FileSlidesIcon.svg?raw";
import FileImageIcon from "../icons/FileImageIcon.svg?raw";
import FileVideoIcon from "../icons/FileVideoIcon.svg?raw";
import FileAudioIcon from "../icons/FileAudioIcon.svg?raw";
import FileArchiveIcon from "../icons/FileArchiveIcon.svg?raw";
import FileCodeIcon from "../icons/FileCodeIcon.svg?raw";
import FileSvgIcon from "../icons/FileSvgIcon.svg?raw";
import FileFontIcon from "../icons/FileFontIcon.svg?raw";
import TreeIcon from "../icons/TreeIcon.svg?raw";
import SearchMinusIcon from "../icons/SearchMinusIcon.svg?raw";
import SearchPlusIcon from "../icons/SearchPlusIcon.svg?raw";
import SunIcon from "../icons/SunIcon.svg?raw";
import MoonIcon from "../icons/MoonIcon.svg?raw";
import HomeIcon from "../icons/HomeIcon.svg?raw";
import StarIcon from "../icons/StarIcon.svg?raw";
import UserIcon from "../icons/UserIcon.svg?raw";
import UserPlusIcon from "../icons/UserPlusIcon.svg?raw";
import UserMinusIcon from "../icons/UserMinusIcon.svg?raw";
import TagIcon from "../icons/TagIcon.svg?raw";
import EnvelopeIcon from "../icons/EnvelopeIcon.svg?raw";
import PhoneIcon from "../icons/PhoneIcon.svg?raw";
import LaptopIcon from "../icons/LaptopIcon.svg?raw";
import SmartphoneIcon from "../icons/SmartphoneIcon.svg?raw";
import HeadphonesIcon from "../icons/HeadphonesIcon.svg?raw";
import PlaneIcon from "../icons/PlaneIcon.svg?raw";
import KeyIcon from "../icons/KeyIcon.svg?raw";
import ShieldIcon from "../icons/ShieldIcon.svg?raw";
import FlagIcon from "../icons/FlagIcon.svg?raw";
import GlobeIcon from "../icons/GlobeIcon.svg?raw";
import MapIcon from "../icons/MapIcon.svg?raw";
import SparklesIcon from "../icons/SparklesIcon.svg?raw";
import LightbulbIcon from "../icons/LightbulbIcon.svg?raw";
import WrenchIcon from "../icons/WrenchIcon.svg?raw";
import CameraIcon from "../icons/CameraIcon.svg?raw";
import CloudIcon from "../icons/CloudIcon.svg?raw";
import CloudSunIcon from "../icons/CloudSunIcon.svg?raw";
import CloudMoonIcon from "../icons/CloudMoonIcon.svg?raw";
import SunCloudIcon from "../icons/SunCloudIcon.svg?raw";
import MoonCloudIcon from "../icons/MoonCloudIcon.svg?raw";
import CloudRainIcon from "../icons/CloudRainIcon.svg?raw";
import CloudSleetIcon from "../icons/CloudSleetIcon.svg?raw";
import CloudSnowIcon from "../icons/CloudSnowIcon.svg?raw";
import SkiIcon from "../icons/SkiIcon.svg?raw";
import SkiBootIcon from "../icons/SkiBootIcon.svg?raw";
import SkiPolesIcon from "../icons/SkiPolesIcon.svg?raw";
import SnowboardIcon from "../icons/SnowboardIcon.svg?raw";
import IceSkateIcon from "../icons/IceSkateIcon.svg?raw";
import SledIcon from "../icons/SledIcon.svg?raw";
import CloudLightningIcon from "../icons/CloudLightningIcon.svg?raw";
import CloudFogIcon from "../icons/CloudFogIcon.svg?raw";
import DropletIcon from "../icons/DropletIcon.svg?raw";
import WindIcon from "../icons/WindIcon.svg?raw";
import ThermometerIcon from "../icons/ThermometerIcon.svg?raw";
import GiftIcon from "../icons/GiftIcon.svg?raw";
import WalletIcon from "../icons/WalletIcon.svg?raw";
import CartIcon from "../icons/CartIcon.svg?raw";
import BookIcon from "../icons/BookIcon.svg?raw";
import GraduationCapIcon from "../icons/GraduationCapIcon.svg?raw";
import MegaphoneIcon from "../icons/MegaphoneIcon.svg?raw";
import EyeIcon from "../icons/EyeIcon.svg?raw";
import SunMoonIcon from "../icons/SunMoonIcon.svg?raw";
import GithubIcon from "../icons/GithubIcon.svg?raw";
import LinkedinIcon from "../icons/LinkedinIcon.svg?raw";
import DollarIcon from "../icons/DollarIcon.svg?raw";
import DatabaseIcon from "../icons/DatabaseIcon.svg?raw";
import DesktopIcon from "../icons/DesktopIcon.svg?raw";
import BullseyeIcon from "../icons/BullseyeIcon.svg?raw";
import ThumbsUpIcon from "../icons/ThumbsUpIcon.svg?raw";
import ThumbsDownIcon from "../icons/ThumbsDownIcon.svg?raw";
import VerifiedIcon from "../icons/VerifiedIcon.svg?raw";
import ChartBarIcon from "../icons/ChartBarIcon.svg?raw";
import ChartPieIcon from "../icons/ChartPieIcon.svg?raw";
import FolderOpenIcon from "../icons/FolderOpenIcon.svg?raw";
import FolderPlusIcon from "../icons/FolderPlusIcon.svg?raw";
import FileEditIcon from "../icons/FileEditIcon.svg?raw";
import FileExportIcon from "../icons/FileExportIcon.svg?raw";
import FileImportIcon from "../icons/FileImportIcon.svg?raw";
import FileExcelIcon from "../icons/FileExcelIcon.svg?raw";
import SignOutIcon from "../icons/SignOutIcon.svg?raw";
import ArrowsAltIcon from "../icons/ArrowsAltIcon.svg?raw";
import WindowMinimizeIcon from "../icons/WindowMinimizeIcon.svg?raw";
import WindowMaximizeIcon from "../icons/WindowMaximizeIcon.svg?raw";
import CalendarMinusIcon from "../icons/CalendarMinusIcon.svg?raw";
import CalendarTimesIcon from "../icons/CalendarTimesIcon.svg?raw";
import CircleIcon from "../icons/CircleIcon.svg?raw";
import CircleFillIcon from "../icons/CircleFillIcon.svg?raw";
import StopIcon from "../icons/StopIcon.svg?raw";
import ListCheckIcon from "../icons/ListCheckIcon.svg?raw";
import SortNumericUpIcon from "../icons/SortNumericUpIcon.svg?raw";
import SortNumericDownIcon from "../icons/SortNumericDownIcon.svg?raw";
import AddressBookIcon from "../icons/AddressBookIcon.svg?raw";
import PenToSquareIcon from "../icons/PenToSquareIcon.svg?raw";
import SlidersHIcon from "../icons/SlidersHIcon.svg?raw";
import ThLargeIcon from "../icons/ThLargeIcon.svg?raw";
import SaveIcon from "../icons/SaveIcon.svg?raw";
import CommentsIcon from "../icons/CommentsIcon.svg?raw";
import VolumeDownIcon from "../icons/VolumeDownIcon.svg?raw";
import FacebookIcon from "../icons/FacebookIcon.svg?raw";
import SnapchatIcon from "../icons/SnapchatIcon.svg?raw";
import YoutubeIcon from "../icons/YoutubeIcon.svg?raw";
import HuggingFaceIcon from "../icons/HuggingFaceIcon.svg?raw";
import NpmIcon from "../icons/NpmIcon.svg?raw";
import PinterestIcon from "../icons/PinterestIcon.svg?raw";
import RedditIcon from "../icons/RedditIcon.svg?raw";
import TwitterIcon from "../icons/TwitterIcon.svg?raw";
import InstagramIcon from "../icons/InstagramIcon.svg?raw";
import TiktokIcon from "../icons/TiktokIcon.svg?raw";
import ThreadsIcon from "../icons/ThreadsIcon.svg?raw";
import BlueskyIcon from "../icons/BlueskyIcon.svg?raw";
import MastodonIcon from "../icons/MastodonIcon.svg?raw";
import DiscordIcon from "../icons/DiscordIcon.svg?raw";
import SlackIcon from "../icons/SlackIcon.svg?raw";
import TelegramIcon from "../icons/TelegramIcon.svg?raw";
import WhatsappIcon from "../icons/WhatsappIcon.svg?raw";
import TwitchIcon from "../icons/TwitchIcon.svg?raw";
import SpotifyIcon from "../icons/SpotifyIcon.svg?raw";
import VimeoIcon from "../icons/VimeoIcon.svg?raw";
import GitlabIcon from "../icons/GitlabIcon.svg?raw";
import BitbucketIcon from "../icons/BitbucketIcon.svg?raw";
import StackOverflowIcon from "../icons/StackOverflowIcon.svg?raw";
import MediumIcon from "../icons/MediumIcon.svg?raw";
import DevToIcon from "../icons/DevToIcon.svg?raw";
import DribbbleIcon from "../icons/DribbbleIcon.svg?raw";
import BehanceIcon from "../icons/BehanceIcon.svg?raw";
import FigmaIcon from "../icons/FigmaIcon.svg?raw";
import OrcidIcon from "../icons/OrcidIcon.svg?raw";
import VippsIcon from "../icons/VippsIcon.svg?raw";
import MicrosoftIcon from "../icons/MicrosoftIcon.svg?raw";
import GoogleIcon from "../icons/GoogleIcon.svg?raw";
import AzureIcon from "../icons/AzureIcon.svg?raw";
import OpentelemetryIcon from "../icons/OpentelemetryIcon.svg?raw";
import PrometheusIcon from "../icons/PrometheusIcon.svg?raw";
import LokiIcon from "../icons/LokiIcon.svg?raw";
import ElasticIcon from "../icons/ElasticIcon.svg?raw";
import SyslogIcon from "../icons/SyslogIcon.svg?raw";
import AnthropicIcon from "../icons/AnthropicIcon.svg?raw";
import ScaleIcon from "../icons/ScaleIcon.svg?raw";
import RadarIcon from "../icons/RadarIcon.svg?raw";
import WorkflowIcon from "../icons/WorkflowIcon.svg?raw";
import PlugIcon from "../icons/PlugIcon.svg?raw";
import KanbanIcon from "../icons/KanbanIcon.svg?raw";
import EqualIcon from "../icons/EqualIcon.svg?raw";
import TagsIcon from "../icons/TagsIcon.svg?raw";
import GitCompareIcon from "../icons/GitCompareIcon.svg?raw";
import MountainSnowIcon from "../icons/MountainSnowIcon.svg?raw";
import MountainIcon from "../icons/MountainIcon.svg?raw";
import SportShoeIcon from "../icons/SportShoeIcon.svg?raw";
import PackageIcon from "../icons/PackageIcon.svg?raw";
import BackpackIcon from "../icons/BackpackIcon.svg?raw";
import SchoolIcon from "../icons/SchoolIcon.svg?raw";
import WhistleIcon from "../icons/WhistleIcon.svg?raw";
import PersonStandingIcon from "../icons/PersonStandingIcon.svg?raw";
import BabyIcon from "../icons/BabyIcon.svg?raw";
import UsersRoundIcon from "../icons/UsersRoundIcon.svg?raw";
import TreesIcon from "../icons/TreesIcon.svg?raw";
import TimerIcon from "../icons/TimerIcon.svg?raw";
import SnowflakeIcon from "../icons/SnowflakeIcon.svg?raw";

import type { IconType } from "@/types/icon.types";
import { parseIcon, sanitizeSvg } from "../icons/iconMarkup";

const { icon } = defineProps<{
  /**
   * A glyph name from IconType, or any other string: one starting with <svg is drawn as a sanitized inline svg in the glyph box, anything else as text, an emoji or ascii art, fitted to the glyph box.
   */
  icon?: IconType | string;
}>();

const iconCtx = computed(() => {
  switch (icon) {
    case "activity":
      return ActivityIcon;
    case "arrow-left":
      return ArrowLeftIcon;
    case "attach-file":
      return AttachFileIcon;
    case "bolt":
      return BoltIcon;
    case "arrow-right":
      return ArrowRightIcon;
    case "avatar":
      return AvatarIcon;
    case "block-filter":
      return BlockFilterIcon;
    case "briefcase-business":
      return BriefcaseBusinessIcon;
    case "building":
      return BuildingIcon;
    case "calendar":
      return CalendarIcon;
    case "calendar-clock":
      return CalendarClockIcon;
    case "calendar-month":
      return CalendarMonthIcon;
    case "calendar-range":
      return CalendarRangeIcon;
    case "calendar-today":
      return CalendarTodayIcon;
    case "calendar-week":
      return CalendarWeekIcon;
    case "chart-line":
      return ChartLineIcon;
    case "check":
      return CheckIcon;
    case "collapse-all":
      return CollapseAllIcon;
    case "chevron-down":
      return ChevronDownIcon;
    case "chevron-first":
      return ChevronFirstIcon;
    case "chevron-last":
      return ChevronLastIcon;
    case "chevron-left":
      return ChevronLeftIcon;
    case "chevron-right":
      return ChevronRightIcon;
    case "chevrons-collapse":
      return ChevronsCollapseIcon;
    case "chevrons-expand":
      return ChevronsExpandIcon;
    case "chevron-up":
      return ChevronUpIcon;
    case "circle-arrow-right":
      return CircleArrowRightIcon;
    case "circle-check":
      return CircleCheckIcon;
    case "circle-error":
      return CircleErrorIcon;
    case "circle-help":
      return CircleHelpIcon;
    case "circle-plus":
      return CirclePlusIcon;
    case "circle-user":
      return CircleUserIcon;
    case "clock":
      return ClockIcon;
    case "cloud-upload":
      return CloudUploadIcon;
    case "construction":
      return ConstructionIcon;
    case "cross":
      return CrossIcon;
    case "dashboard":
      return DashboardIcon;
    case "download":
      return DownloadIcon;
    case "expand-all":
      return ExpandAllIcon;
    case "expand":
      return ExpandIcon;
    case "file":
      return FileIcon;
    case "filter":
      return FilterIcon;
    case "flashlight":
      return FlashlightIcon;
    case "flashlight-off":
      return FlashlightOffIcon;
    case "flow":
      return FlowIcon;
    case "full-screen":
      return FullScreenIcon;
    case "full-width":
      return FullWidthIcon;
    case "graph":
      return GraphIcon;
    case "group":
      return GroupIcon;
    case "heart":
      return HeartIcon;
    case "house-add":
      return HouseAddIcon;
    case "image":
      return ImageIcon;
    case "info":
      return InfoIcon;
    case "keyboard":
      return KeyboardIcon;
    case "list-filter":
      return ListFilterIcon;
    case "list":
      return ListIcon;
    case "lock":
      return LockIcon;
    case "lock-open":
      return LockOpenIcon;
    case "logo":
      return LogoIcon;
    case "low-priority":
      return LowPriorityIcon;
    case "map-pin":
      return MapPinIcon;
    case "menu":
      return MenuIcon;
    case "message-warning":
      return MessageWarningIcon;
    case "mic":
      return MicIcon;
    case "minus":
      return MinusIcon;
    case "more-vert":
      return MoreVertIcon;
    case "music":
      return MusicIcon;
    case "play":
      return PlayIcon;
    case "volume-up":
      return VolumeUpIcon;
    case "volume-off":
      return VolumeOffIcon;
    case "newspaper":
      return NewspaperIcon;
    case "not-found":
      return NotFoundIcon;
    case "notification":
      return NotificationIcon;
    case "open-in-new":
      return OpenInNewIcon;
    case "pause":
      return PauseIcon;
    case "pencil":
      return PencilIcon;
    case "pentagon":
      return PentagonIcon;
    case "plus":
      return PlusIcon;
    case "printer":
      return PrinterIcon;
    case "qr-code":
      return QrCodeIcon;
    case "redo":
      return RedoIcon;
    case "repeat":
      return RepeatIcon;
    case "search":
      return SearchIcon;
    case "sdk":
      return SdkIcon;
    case "send":
      return SendIcon;
    case "settings":
      return SettingsIcon;
    case "sidebar":
      return SidebarIcon;
    case "share":
      return ShareIcon;
    case "shield-check":
      return ShieldCheckIcon;
    case "shield-user":
      return ShieldUserIcon;
    case "shrink":
      return ShrinkIcon;
    case "sort":
      return SortIcon;
    case "square-activity":
      return SquareActivityIcon;
    case "square-dashed":
      return SquareDashedIcon;
    case "store":
      return StoreIcon;
    case "trash":
      return TrashIcon;
    case "triangle-alert":
      return TriangleAlertIcon;
    case "undo":
      return UndoIcon;
    case "upload":
      return UploadIcon;
    case "users":
      return UsersIcon;
    case "webhooks":
      return WebhooksIcon;
    case "zoom-in":
      return ZoomInIcon;
    case "zoom-out":
      return ZoomOutIcon;
    case "align-left":
      return AlignLeftIcon;
    case "align-center":
      return AlignCenterIcon;
    case "align-right":
      return AlignRightIcon;
    case "align-justify":
      return AlignJustifyIcon;
    case "calendar-plus":
      return CalendarPlusIcon;
    case "credit-card":
      return CreditCardIcon;
    case "ellipsis-h":
      return EllipsisHIcon;
    case "chevrons-left":
      return ChevronsLeftIcon;
    case "chevrons-right":
      return ChevronsRightIcon;
    case "arrow-up":
      return ArrowUpIcon;
    case "arrow-down":
      return ArrowDownIcon;
    case "arrows-horizontal":
      return ArrowsHorizontalIcon;
    case "at":
      return AtIcon;
    case "bookmark":
      return BookmarkIcon;
    case "box":
      return BoxIcon;
    case "check-square":
      return CheckSquareIcon;
    case "square":
      return SquareIcon;
    case "code":
      return CodeIcon;
    case "comment":
      return CommentIcon;
    case "copy":
      return CopyIcon;
    case "file-pdf":
      return FilePdfIcon;
    case "hashtag":
      return HashtagIcon;
    case "heading-1":
      return Heading1Icon;
    case "heading-2":
      return Heading2Icon;
    case "heading-3":
      return Heading3Icon;
    case "heading-4":
      return Heading4Icon;
    case "id-card":
      return IdCardIcon;
    case "images":
      return ImagesIcon;
    case "unlink":
      return UnlinkIcon;
    case "link":
      return LinkIcon;
    case "palette":
      return PaletteIcon;
    case "refresh":
      return RefreshIcon;
    case "sitemap":
      return SitemapIcon;
    case "stop-circle":
      return StopCircleIcon;
    case "table":
      return TableIcon;
    case "text-height":
      return TextHeightIcon;
    case "video":
      return VideoIcon;
    case "grip-vertical":
      return GripVerticalIcon;
    case "folder":
      return FolderIcon;
    case "file-text":
      return FileTextIcon;
    case "file-markdown":
      return FileMarkdownIcon;
    case "file-word":
      return FileWordIcon;
    case "file-sheet":
      return FileSheetIcon;
    case "file-csv":
      return FileCsvIcon;
    case "file-slides":
      return FileSlidesIcon;
    case "file-image":
      return FileImageIcon;
    case "file-video":
      return FileVideoIcon;
    case "file-audio":
      return FileAudioIcon;
    case "file-archive":
      return FileArchiveIcon;
    case "file-code":
      return FileCodeIcon;
    case "file-svg":
      return FileSvgIcon;
    case "file-font":
      return FileFontIcon;
    case "tree":
      return TreeIcon;
    case "search-minus":
      return SearchMinusIcon;
    case "search-plus":
      return SearchPlusIcon;
    case "sun":
      return SunIcon;
    case "moon":
      return MoonIcon;
    case "home":
      return HomeIcon;
    case "star":
      return StarIcon;
    case "user":
      return UserIcon;
    case "user-plus":
      return UserPlusIcon;
    case "user-minus":
      return UserMinusIcon;
    case "tag":
      return TagIcon;
    case "envelope":
      return EnvelopeIcon;
    case "phone":
      return PhoneIcon;
    case "laptop":
      return LaptopIcon;
    case "smartphone":
      return SmartphoneIcon;
    case "headphones":
      return HeadphonesIcon;
    case "plane":
      return PlaneIcon;
    case "key":
      return KeyIcon;
    case "shield":
      return ShieldIcon;
    case "flag":
      return FlagIcon;
    case "globe":
      return GlobeIcon;
    case "map":
      return MapIcon;
    case "sparkles":
      return SparklesIcon;
    case "lightbulb":
      return LightbulbIcon;
    case "wrench":
      return WrenchIcon;
    case "camera":
      return CameraIcon;
    case "cloud":
      return CloudIcon;
    case "cloud-sun":
      return CloudSunIcon;
    case "cloud-moon":
      return CloudMoonIcon;
    case "sun-cloud":
      return SunCloudIcon;
    case "moon-cloud":
      return MoonCloudIcon;
    case "cloud-rain":
      return CloudRainIcon;
    case "cloud-sleet":
      return CloudSleetIcon;
    case "cloud-snow":
      return CloudSnowIcon;
    case "ski":
      return SkiIcon;
    case "ski-boot":
      return SkiBootIcon;
    case "ski-poles":
      return SkiPolesIcon;
    case "snowboard":
      return SnowboardIcon;
    case "ice-skate":
      return IceSkateIcon;
    case "sled":
      return SledIcon;
    case "cloud-lightning":
      return CloudLightningIcon;
    case "cloud-fog":
      return CloudFogIcon;
    case "droplet":
      return DropletIcon;
    case "wind":
      return WindIcon;
    case "thermometer":
      return ThermometerIcon;
    case "gift":
      return GiftIcon;
    case "wallet":
      return WalletIcon;
    case "cart":
      return CartIcon;
    case "book":
      return BookIcon;
    case "graduation-cap":
      return GraduationCapIcon;
    case "megaphone":
      return MegaphoneIcon;
    case "eye":
      return EyeIcon;
    case "sun-moon":
      return SunMoonIcon;
    case "github":
      return GithubIcon;
    case "linkedin":
      return LinkedinIcon;
    case "dollar":
      return DollarIcon;
    case "database":
      return DatabaseIcon;
    case "desktop":
      return DesktopIcon;
    case "bullseye":
      return BullseyeIcon;
    case "thumbs-up":
      return ThumbsUpIcon;
    case "thumbs-down":
      return ThumbsDownIcon;
    case "verified":
      return VerifiedIcon;
    case "chart-bar":
      return ChartBarIcon;
    case "chart-pie":
      return ChartPieIcon;
    case "folder-open":
      return FolderOpenIcon;
    case "folder-plus":
      return FolderPlusIcon;
    case "file-edit":
      return FileEditIcon;
    case "file-export":
      return FileExportIcon;
    case "file-import":
      return FileImportIcon;
    case "file-excel":
      return FileExcelIcon;
    case "sign-out":
      return SignOutIcon;
    case "arrows-alt":
      return ArrowsAltIcon;
    case "window-minimize":
      return WindowMinimizeIcon;
    case "window-maximize":
      return WindowMaximizeIcon;
    case "calendar-minus":
      return CalendarMinusIcon;
    case "calendar-times":
      return CalendarTimesIcon;
    case "circle":
      return CircleIcon;
    case "circle-fill":
      return CircleFillIcon;
    case "stop":
      return StopIcon;
    case "list-check":
      return ListCheckIcon;
    case "sort-numeric-up":
      return SortNumericUpIcon;
    case "sort-numeric-down":
      return SortNumericDownIcon;
    case "address-book":
      return AddressBookIcon;
    case "pen-to-square":
      return PenToSquareIcon;
    case "sliders-h":
      return SlidersHIcon;
    case "th-large":
      return ThLargeIcon;
    case "save":
      return SaveIcon;
    case "comments":
      return CommentsIcon;
    case "volume-down":
      return VolumeDownIcon;
    case "facebook":
      return FacebookIcon;
    case "snapchat":
      return SnapchatIcon;
    case "youtube":
      return YoutubeIcon;
    case "huggingface":
      return HuggingFaceIcon;
    case "npm":
      return NpmIcon;
    case "pinterest":
      return PinterestIcon;
    case "reddit":
      return RedditIcon;
    case "twitter":
      return TwitterIcon;
    case "instagram":
      return InstagramIcon;
    case "tiktok":
      return TiktokIcon;
    case "threads":
      return ThreadsIcon;
    case "bluesky":
      return BlueskyIcon;
    case "mastodon":
      return MastodonIcon;
    case "discord":
      return DiscordIcon;
    case "slack":
      return SlackIcon;
    case "telegram":
      return TelegramIcon;
    case "whatsapp":
      return WhatsappIcon;
    case "twitch":
      return TwitchIcon;
    case "spotify":
      return SpotifyIcon;
    case "vimeo":
      return VimeoIcon;
    case "gitlab":
      return GitlabIcon;
    case "bitbucket":
      return BitbucketIcon;
    case "stackoverflow":
      return StackOverflowIcon;
    case "medium":
      return MediumIcon;
    case "devto":
      return DevToIcon;
    case "dribbble":
      return DribbbleIcon;
    case "behance":
      return BehanceIcon;
    case "figma":
      return FigmaIcon;
    case "orcid":
      return OrcidIcon;
    case "vipps":
      return VippsIcon;
    case "microsoft":
      return MicrosoftIcon;
    case "google":
      return GoogleIcon;
    case "azure":
      return AzureIcon;
    case "opentelemetry":
      return OpentelemetryIcon;
    case "prometheus":
      return PrometheusIcon;
    case "loki":
      return LokiIcon;
    case "elastic":
      return ElasticIcon;
    case "syslog":
      return SyslogIcon;
    case "anthropic":
      return AnthropicIcon;
    case "scale":
      return ScaleIcon;
    case "radar":
      return RadarIcon;
    case "workflow":
      return WorkflowIcon;
    case "plug":
      return PlugIcon;
    case "kanban":
      return KanbanIcon;
    case "equal":
      return EqualIcon;
    case "tags":
      return TagsIcon;
    case "git-compare":
      return GitCompareIcon;
    case "mountain-snow":
      return MountainSnowIcon;
    case "mountain":
      return MountainIcon;
    case "sport-shoe":
      return SportShoeIcon;
    case "package":
      return PackageIcon;
    case "backpack":
      return BackpackIcon;
    case "school":
      return SchoolIcon;
    case "whistle":
      return WhistleIcon;
    case "person-standing":
      return PersonStandingIcon;
    case "baby":
      return BabyIcon;
    case "users-round":
      return UsersRoundIcon;
    case "trees":
      return TreesIcon;
    case "timer":
      return TimerIcon;
    case "snowflake":
      return SnowflakeIcon;
    default:
      return null;
  }
});

const isSvg = computed(() => !iconCtx.value && !!icon && icon.trim().toLowerCase().startsWith("<svg"));

const parsed = computed(() => {
  if (iconCtx.value) return parseIcon(iconCtx.value);
  if (!isSvg.value || !icon) return null;
  const clean = sanitizeSvg(icon);
  return clean ? parseIcon(clean) : null;
});

const text = computed(() => (iconCtx.value || isSvg.value || !icon?.trim() ? null : icon.replace(/^(?:[ \t]*\n)+/, "").replace(/\s+$/, "")));

const emoji = /\p{Extended_Pictographic}(?:\uFE0F|\p{Emoji_Modifier})?(?:\u200D\p{Extended_Pictographic}(?:\uFE0F|\p{Emoji_Modifier})?)*|\p{Regional_Indicator}{1,2}/gu;

const textBox = computed(() => {
  if (!text.value) return null;
  const lines = text.value.split("\n");
  const cols = Math.max(
    1,
    ...lines.map((line) => (line.match(emoji)?.length ?? 0) * 2.2 + Array.from(line.replace(emoji, "").replace(/[\uFE0F\u200D]/g, "")).length),
  );
  return { "--mar-icon-text-lines": lines.length, "--mar-icon-text-cols": cols };
});
</script>

<template>
  <svg v-if="parsed" class="mar-icon" v-bind="parsed.attrs" v-html="parsed.inner" />
  <span v-else-if="text" class="mar-icon mar-icon-text" :style="textBox" role="img" :aria-label="text"><span class="mar-icon-text-glyph">{{ text }}</span></span>
</template>

<style scoped>
.mar-icon {
  width: 0.875em;
  height: 0.875em;
  flex-shrink: 0;
}

.mar-icon-text {
  display: inline-grid;
  place-items: center;
  overflow: hidden;
  container-type: size;
  vertical-align: middle;
  line-height: 1;
}

.mar-icon-text-glyph {
  font-family: var(--mar-font-mono, monospace);
  font-size: min(
    calc(100cqh / var(--mar-icon-text-lines)),
    calc(100cqw / (var(--mar-icon-text-cols) * 0.6))
  );
  line-height: 1;
  white-space: pre;
  text-align: start;
}

.mar-icon.mar-icon-medium {
  width: 1em;
  height: 1em;
}

.mar-icon.mar-icon-large {
  width: 1.125em;
  height: 1.125em;
}

.mar-icon.mar-icon-xlarge {
  width: 1.5em;
  height: 1.5em;
}

.mar-icon.mar-icon-xxlarge {
  width: 2em;
  height: 2em;
}

.mar-icon.mar-icon-xxxlarge {
  width: 4em;
  height: 4em;
}

.mar-icon.mar-icon-scale {
  width: 100%;
  height: 100%;
}
</style>
